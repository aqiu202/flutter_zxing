import 'dart:isolate';
import 'dart:math';

import 'package:camera/camera.dart';

import 'flutter_zxing.dart';

// Inspired from https://github.com/am15h/object_detection_flutter

/// Bundles data to pass between Isolate
class IsolateData {
  CameraImage cameraImage;
  int format;
  double cropPercent;
  bool fullScreen;

  SendPort? responsePort;

  IsolateData(
      {required this.cameraImage,
      required this.format,
      this.cropPercent = 0.6,
      this.fullScreen = false});
}

/// Manages separate Isolate instance for inference
class EventListener {
  static const String kDebugName = "ZxingIsolate";

  // ignore: unused_field
  late Isolate _isolate;
  final _receivePort = ReceivePort();
  late SendPort _sendPort;

  SendPort get sendPort => _sendPort;

  Future<void> start() async {
    _isolate = await Isolate.spawn<SendPort>(
      entryPoint,
      _receivePort.sendPort,
      debugName: kDebugName,
    );

    _sendPort = await _receivePort.first;
  }

  void stop() {
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
  }

  static void entryPoint(SendPort sendPort) async {
    final port = ReceivePort();
    sendPort.send(port.sendPort);
    await for (final IsolateData? data in port) {
      if (data != null) {
        try {
          final image = data.cameraImage;
          final cropPercent = data.cropPercent;
          final bytes = await convertImage(image);
          final cropSize =
              (min(image.width, image.height) * cropPercent).round();
          final width = data.fullScreen ? image.width : cropSize;
          final height = data.fullScreen ? image.height : cropSize;
          final result = FlutterZxing.readBarcode(bytes, data.format,
              image.width, image.height, width, height);
          data.responsePort?.send(result);
        } on Exception catch (e) {
          data.responsePort?.send(e);
        }
      }
    }
  }
}
