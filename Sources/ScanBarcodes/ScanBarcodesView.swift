import AVFoundation
import SwiftUI

public enum BarcodeScanError: Error {
    case camera, barcodeRecognizer
}

public struct ScanBarcodesView: UIViewControllerRepresentable {
    @Binding var zoomLevel: Int
    @Binding var flashlightOn: Bool

    public let barcodeTypes: [AVMetadataMachineReadableCodeObject.ObjectType]
    public var completion: (Result<String, BarcodeScanError>) -> Void
    public var scanRateDelay: Double

    public init(
        barcodeTypes: [AVMetadataMachineReadableCodeObject.ObjectType],
        zoomLevel : Binding<Int> = .constant(1),
        flashlightOn: Binding<Bool> = .constant(false),
        scanRateDelay: Double = 5,
        completion: @escaping (Result<String, BarcodeScanError>) -> Void) {
            self.barcodeTypes = barcodeTypes
            self._zoomLevel = zoomLevel
            self._flashlightOn = flashlightOn
            self.completion = completion
            self.scanRateDelay = scanRateDelay
        }

    public func makeCoordinator() -> ScanBarcodesCoordinator {
        return ScanBarcodesCoordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> ScanBarcodesViewController {
        let viewC = ScanBarcodesViewController(flashlightOn, zoomLevel)
        viewC.delegate = context.coordinator
        return viewC
    }

    public func updateUIViewController(_ uiViewController: ScanBarcodesViewController, context: Context) {
        // update flashlight and zoom level
        guard let _ = AVCaptureDevice.default(for: .video) else {
            return
        }
        if uiViewController.flashlightOn != flashlightOn ||
            uiViewController.zoomLevel != zoomLevel {
            uiViewController.configure(
                flashlightOn: flashlightOn,
                zoomLevel: zoomLevel)
        }
    }


    public class ScanBarcodesCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: ScanBarcodesView
        private var lastBarcodeScanned: String = ""
        private var lastScanTime: Date = Date()

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
            // only call completion handler if the barcode has changed or the scanRateDelay seconds have passed
            if (barcodeValue != lastBarcodeScanned || lastScanTime.timeIntervalSinceNow < -parent.scanRateDelay) {
                // reset tracking variables to current values (code & time)
                lastBarcodeScanned = barcodeValue
                lastScanTime = Date()
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                parent.completion(.success(barcodeValue))
            }
            
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
        var flashlightOn: Bool
        var zoomLevel: Int

        required init?(coder: NSCoder) {
            self.flashlightOn = false
            self.zoomLevel = 1
            super.init(coder: coder)
        }

        public init(_ flashlightOn: Bool = false, _ zoomLevel:Int = 1) {
            self.flashlightOn = flashlightOn
            self.zoomLevel = zoomLevel
            super.init(nibName: nil, bundle: nil)
        }

        public override func viewDidLoad() {
            super.viewDidLoad()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateOrientation),
                name: Notification.Name("UIDeviceOrientationDidChangeNotification"),
                object: nil
            )
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
            NotificationCenter.default.removeObserver(self)
            super.viewWillDisappear(animated)
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateOrientation()
        }

        override public func viewWillLayoutSubviews() {
            previewLayer?.frame = view.layer.bounds
        }

        public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: { (UIViewControllerTransitionCoordinatorContext) -> Void in
                self.previewLayer.connection?.videoOrientation = self.videoOrientationFromCurrentDeviceOrientation()

            }, completion: { (UIViewControllerTransitionCoordinatorContext) -> Void in
                // Finish Rotation
            })

            super.viewWillTransition(to: size, with: coordinator)
        }

        public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return .all
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
            safelySetTorch(device, mode: flashlightOn ? AVCaptureDevice.TorchMode.on : AVCaptureDevice.TorchMode.off)
            device.videoZoomFactor = CGFloat(zoomLevel)
            device.unlockForConfiguration()
        }

        func configure(flashlightOn: Bool, zoomLevel: Int) {
            self.flashlightOn = flashlightOn
            self.zoomLevel = zoomLevel
            guard let device = AVCaptureDevice.default(for: .video)
            else { return }

            do {
                try device.lockForConfiguration()
                safelySetTorch(device, mode: flashlightOn ? .on : .off)
                device.videoZoomFactor = CGFloat(zoomLevel)
                device.unlockForConfiguration()
            } catch let error {
                print(error.localizedDescription)
            }
        }

        func safelySetTorch(_ device: AVCaptureDevice, mode: AVCaptureDevice.TorchMode) {
            if device.isTorchModeSupported(mode) {
                device.torchMode = mode
            }
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
                        self.configure(
                            flashlightOn: self.flashlightOn,
                            zoomLevel: self.zoomLevel
                        )
                    }

                    guard let videoDeviceInput = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(videoDeviceInput) else {
                        return
                    }
                    captureSession.addInput(videoDeviceInput)

                    DispatchQueue.main.async {  [weak self] in
                        self?.previewLayer.connection?.videoOrientation =
                        self?.videoOrientationFromCurrentDeviceOrientation() ?? .portrait
                    }

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

        func videoOrientationFromCurrentDeviceOrientation() -> AVCaptureVideoOrientation {
            guard let deviceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                return .portrait
            }
            switch deviceOrientation {
            case .portrait:
                return AVCaptureVideoOrientation.portrait
            case .landscapeLeft:
                return AVCaptureVideoOrientation.landscapeLeft
            case .landscapeRight:
                return AVCaptureVideoOrientation.landscapeRight
            case .portraitUpsideDown:
                return AVCaptureVideoOrientation.portraitUpsideDown
            default:
                return AVCaptureVideoOrientation.portrait
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
