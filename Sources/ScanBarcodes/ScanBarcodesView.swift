//
//  ScanBarcodesView.swift
//  
//
//  Created by Mark Powell on 4/15/21.
//

import AVFoundation
import SwiftUI


public struct ScanBarcodesView: UIViewControllerRepresentable {

    public enum BarcodeScanError: Error {
        case camera, barcodeRecognizer
    }

    public let barcodeTypes: [AVMetadataMachineReadableCodeObject.ObjectType]
    public let scanInterval: Double
    public var completion: (Result<String, BarcodeScanError>) -> Void

    public init(
        barcodeTypes: [AVMetadataMachineReadableCodeObject.ObjectType],
        scanInterval: Double = 1.0,
        completion: @escaping (Result<String, BarcodeScanError>) -> Void) {
        self.barcodeTypes = barcodeTypes
        self.scanInterval = scanInterval
        self.completion = completion
    }

    public func makeCoordinator() -> ScanBarcodesCoordinator {
        return ScanBarcodesCoordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> ScanBarcodesViewController {
        let viewC = ScanBarcodesViewController()
        viewC.delegate = context.coordinator
        return viewC
    }

    public func updateUIViewController(_ uiViewController: ScanBarcodesViewController, context: Context) {
        // nothing to do
    }


    public class ScanBarcodesCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: ScanBarcodesView

        init(parent: ScanBarcodesView) {
            self.parent = parent
        }

        public func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let barcodeValue = readableObject.stringValue else { return }
                recognized(barcodeValue)
            }
        }

        func recognized(_ barcodeValue: String) {
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            parent.completion(.success(barcodeValue))

        }

        func failed(error: BarcodeScanError) {
            parent.completion(.failure(error))
        }
    }

    public class ScanBarcodesViewController: UIViewController {
        var delegate: ScanBarcodesCoordinator?
        var captureSession = AVCaptureSession()
        let photoOutput = AVCapturePhotoOutput()
        let serialQueue = DispatchQueue(label: "AVCaptureSession")
        let barcodeQueue = DispatchQueue(label: "BarcodeDetection")
        var previewLayer: AVCaptureVideoPreviewLayer!

        public override func viewDidLoad() {
            super.viewDidLoad()
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(updateOrientation),
                                                   name: Notification.Name("UIDeviceOrientationDidChangeNotification"),
                                                   object: nil)

        }

        override public func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            if previewLayer == nil {
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            }
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            startCameraSession()
        }

        override public func viewWillDisappear(_ animated: Bool) {
            stopSessionAndRemoveCameraInputOutput()
            super.viewWillDisappear(animated)
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateOrientation()
        }

        override public func viewWillLayoutSubviews() {
            previewLayer?.frame = view.layer.bounds
        }

        @objc func updateOrientation() {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else { return }
            guard let connection = captureSession.connections.last, connection.isVideoOrientationSupported else { return }
            connection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) ?? .portrait
        }

        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.first?.view == view,
                  let touchPoint = touches.first,
                  let device = AVCaptureDevice.default(for: .video)
            else { return }

            let videoView = view
            let screenSize = videoView!.bounds.size
            let xPoint = touchPoint.location(in: videoView).y / screenSize.height
            let yPoint = 1.0 - touchPoint.location(in: videoView).x / screenSize.width
            let focusPoint = CGPoint(x: xPoint, y: yPoint)

            do {
                try device.lockForConfiguration()
            } catch {
                return
            }

            // Focus to the correct point, make continiuous focus and exposure so the point stays sharp when moving the device closer
            device.focusPointOfInterest = focusPoint
            device.focusMode = .continuousAutoFocus
            device.exposurePointOfInterest = focusPoint
            device.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
            device.unlockForConfiguration()
        }

        func startCameraSession() {
            serialQueue.async {
                let captureSession = self.captureSession
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                    captureSession.beginConfiguration()
                    defer {
                        captureSession.commitConfiguration()
                        captureSession.startRunning()
                        DispatchQueue.main.async {
                            guard !captureSession.inputs.isEmpty else {
                                return
                            }
                            self.previewLayer.session = captureSession
                        }
                    }

                    guard let videoDeviceInput = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(videoDeviceInput) else {
                        return
                    }
                    captureSession.addInput(videoDeviceInput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    guard captureSession.canAddOutput(self.photoOutput) else {
                        return
                    }
                    captureSession.sessionPreset = .photo
                    captureSession.addOutput(self.photoOutput)

                    let captureMetadataOutput = AVCaptureMetadataOutput()
                    captureSession.addOutput(captureMetadataOutput)
                    captureMetadataOutput.setMetadataObjectsDelegate(self.delegate, queue: self.barcodeQueue)
                    captureMetadataOutput.metadataObjectTypes = self.delegate?.parent.barcodeTypes
                    do {
                        try device.lockForConfiguration()
                        defer { device.unlockForConfiguration() }
                        device.videoZoomFactor = 5.0
                    } catch {
                        print("error setting zoom: \(error.localizedDescription)")
                    }
                }
            }
        }

        func stopSessionAndRemoveCameraInputOutput() {
            serialQueue.sync {
                guard captureSession.isRunning else { return }
                captureSession.stopRunning()
                captureSession.beginConfiguration()
                let cameraInputs = captureSession.inputs.compactMap { $0 as AVCaptureInput }
                cameraInputs.forEach { captureSession.removeInput($0) }
                let cameraOutputs = captureSession.outputs.compactMap { $0 as AVCaptureOutput }
                cameraOutputs.forEach { captureSession.removeOutput($0) }
                captureSession.commitConfiguration()
            }
        }
    }
}

struct ScanBarcodesView_Previews: PreviewProvider {
    static var previews: some View {
        ScanBarcodesView(barcodeTypes: [.qr]) { result in
            //nothing to do
        }
    }
}
