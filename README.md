# flutter_zxing

A barcode and QR code scanner based on [ZXing C++](https://github.com/nu-book/zxing-cpp) library natively in Flutter with Dart FFI.

## Demo Screenshots
<pre>
<img alt="04_trending_repository_screen" src="https://user-images.githubusercontent.com/11523360/167903986-dc69efca-4520-4494-9298-24ea7b3da941.jpg" width="240">&nbsp; <img alt="04_trending_repository_screen" src="https://user-images.githubusercontent.com/11523360/167904002-114d9844-964d-4b84-9ea0-8185ed1d2bb8.jpg" width="240">&nbsp; <img alt="04_trending_repository_screen" src="https://user-images.githubusercontent.com/11523360/167904024-809aa434-c0f5-4069-a223-da78fe48d671.jpg" width="240">&nbsp; 
</pre>

## Supported Barcode Formats

| 1D product | 1D industrial     | 2D
| ---------- | ----------------- | --------------
| UPC-A      | Code 39           | QR Code
| UPC-E      | Code 93           | DataMatrix
| EAN-8      | Code 128          | Aztec
| EAN-13     | Codabar           | PDF417
| DataBar    | ITF               | MaxiCode (beta)
|            | DataBar Expanded  |

## Features
- [x] Read barcode from camera 
- [x] Read barcode from gallery
- [x] Create barcode from text
- [ ] Read multiple barcodes from camera or gallery
- [ ] Return scanned barcode position and size

## Getting Started
### To read barcode:
```dart
import 'package:flutter_zxing/flutter_zxing.dart';

// Use ReaderWidget to quickly read barcode from camera image
@override
Widget build(BuildContext context) {
    return Scaffold(
        body: ReaderWidget(
            onScan: (result) async {
                // Do something with the result
            },
        ),
    ),
);

// Or use FlutterZxing to read barcode from camera image directly
cameraController?.startImageStream((img) async {
    final bytes = await convertImage(img);
    final result = FlutterZxing.readBarcode(bytes, Format.Any, img.width, img.height, 200, 200);
    if (result.isValidBool) {
        debugPrint(result.textString);
    }
    return null;
});
```

### To create barcode:
```dart
import 'package:flutter_zxing/flutter_zxing.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as imglib;

// Use WriterWidget to quickly read barcode from camera image
@override
Widget build(BuildContext context) {
    return Scaffold(
        body: WriterWidget(
            onSuccess: (result, bytes) {
                // Do something with the result
            },
            onError: (error) {
                // Do something with the error
            },
        ),
    ),
);

// Or use FlutterZxing to create barcode directly
final text = 'Text to encode';
final result = FlutterZxing.encodeBarcode(text, 300, 300, Format.QRCode, 10, 0);
if (result.isValidBool) {
    final img = imglib.Image.fromBytes(width, height, result.bytes);
    final encodedBytes = Uint8List.fromList(imglib.encodeJpg(img));
    // use encodedBytes as you wish
}
```

## License

MIT License. See [LICENSE](https://github.com/khoren93/flutter_zxing/blob/master/LICENSE).
