# ScanBarcodes

ScanBarcodes is a SwiftUI view that scans barcodes using an iPhone or iPad camera.

<p>
	<img src="https://img.shields.io/badge/iOS-13.0+-blue.svg" />
	<img src="https://img.shields.io/badge/Swift-5.3-ff69b4.svg" />
</p>

  The framework uses [AVFoundation](https://developer.apple.com/av-foundation/) for high performance video capture and barcode recognition. The view also provides optional control of the flashlight and the zoom level of the camera.

## Getting started

Try the [demo application](https://github.com/nasa-jpl/ScanBarcodesDemo.git)

**Two important notes on usage:**

1. an actual phone is required (iOS simulator doesn't yet support the camera)
2. an entry in the app Info.plist for "Privacy - Camera Usage Description" is required to prompt for user permission to use the camera to scan barcodes.

The view takes two required arguments and two optional arguments:

- ```barcodeTypes: [AVMetadataMachineReadableCodeObject.ObjectType]``` (required)
- ```zoomLevel : Binding<Int>``` (optional, defaults to 1, values greater than 1 increase the zoom)
- ```flashlightOn: Binding<Bool>``` (optional, defaults to false)
- ```completion: @escaping (Result<String, BarcodeScanError>) -> Void)``` (required, a closure to execute when a result is obtained)

## Copyright
Copyright © 2021 California Institute of Technology. ALL RIGHTS
RESERVED. United States Government Sponsorship Acknowledged.

## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Credits

This project was based on [CodeScanner](https://github.com/twostraws/CodeScanner) by Paul Hudson and liberally modified. 
