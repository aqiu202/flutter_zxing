import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_beep/flutter_beep.dart';
import 'package:flutter_zxing/event_listener.dart';

import 'flutter_zxing.dart';

class ZXingCamera extends StatefulWidget {
  ZXingCamera(
      {Key? key,
      required this.onScan,
      this.codeFormat = Format.Any,
      this.beep = false,
      this.showCroppingRect = true,
      this.scanPeriod = const Duration(milliseconds: 200), // 500ms delay
      this.resolveDelay = const Duration(milliseconds: 800), // 500ms delay
      this.cropPercent = 0.6, // 60% of the screen
      this.resolution = ResolutionPreset.high,
      this.fullScreen = false,
      this.controller,
      this.onControllerCreated,
      this.scannerOverlayWidget,
      this.scannerOverlay})
      : super(key: key);

  static Future<void> init() async {
    cameras ??= await availableCameras();
  }

  static List<CameraDescription>? cameras;
  final void Function(CodeResult) onScan;
  final int codeFormat;
  final bool beep;
  final bool showCroppingRect;
  final Duration scanPeriod;
  final Duration resolveDelay;
  final double cropPercent;
  final ResolutionPreset resolution;
  void Function(CameraController)? onControllerCreated;
  Widget? scannerOverlayWidget;
  ScannerOverlay? scannerOverlay;
  CameraController? controller;
  bool fullScreen;

  @override
  State<ZXingCamera> createState() => _ZXingCameraState();
}

class _ZXingCameraState extends State<ZXingCamera> {
  bool get isAndroid => Platform.isAndroid;

  // true when code detecting is ongoing
  bool _isProcessing = false;

  /// Instance of [IsolateUtils]
  late EventListener eventListener;

  @override
  void initState() {
    super.initState();
    initStateAsync();
  }

  void initStateAsync() async {
    // Spawn a new isolate
    eventListener = EventListener();
    await eventListener.start();
    SystemChannels.lifecycle.setMessageHandler((message) async {
      debugPrint(message);
      if (!widget.controller!.value.isInitialized) {
        return;
      }
      if (mounted) {
        if (message == AppLifecycleState.paused.toString()) {
          widget.controller?.pausePreview();
        }
        if (message == AppLifecycleState.resumed.toString()) {
          widget.controller?.resumePreview();
        }
      }
      return;
    });
  }

  void _notPresentThenNewController() {
    widget.controller ??= CameraController(
      ZXingCamera.cameras!.first,
      widget.resolution,
      enableAudio: false,
      imageFormatGroup:
          isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888
    );
  }

  Future<void> _initController() async {
    if (!widget.controller!.value.isInitialized) {
      await widget.controller?.initialize();
    }
  }

  @override
  void dispose() async {
    super.dispose();
    // await controller?.stopImageStream();
    await widget.controller?.dispose();
    eventListener.stop();
  }

  void _callControllerCreated() {
    if (widget.onControllerCreated != null) {
      widget.onControllerCreated!(widget.controller!);
    }
  }

  Future<void> _startImageDataListening() async {
    if (!widget.controller!.value.isStreamingImages) {
      await widget.controller?.startImageStream(_processCameraImage);
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
  }

  void logError(String code, String? message) {
    if (message != null) {
      debugPrint('Error: $code\nError Message: $message');
    } else {
      debugPrint('Error: $code');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!_isProcessing) {
      _isProcessing = true;
      try {
        var isolateData = IsolateData(
            cameraImage: image,
            format: widget.codeFormat,
            cropPercent: widget.cropPercent,
            fullScreen: widget.fullScreen);

        /// perform inference in separate isolate
        CodeResult result = await inference(isolateData);
        if (result.isValidBool) {
          if (widget.beep) {
            FlutterBeep.beep();
          }
          widget.onScan(result);
          await Future.delayed(widget.resolveDelay);
        }
      } on FileSystemException catch (e) {
        debugPrint(e.message);
      } catch (e) {
        debugPrint(e.toString());
      }
      await Future.delayed(widget.scanPeriod);
      _isProcessing = false;
    }
    return;
  }

  /// Runs inference in another isolate
  Future<CodeResult> inference(IsolateData isolateData) async {
    ReceivePort responsePort = ReceivePort();
    eventListener.sendPort
        .send(isolateData..responsePort = responsePort.sendPort);
    var results = await responsePort.first;
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cropSize = min(size.width, size.height) * widget.cropPercent;
    _notPresentThenNewController();
    Widget cameraView = Stack(
      children: [
        // Camera preview
        Center(child: _cameraPreviewWidget(cropSize)),
      ],
    );
    final controllerInitialized = widget.controller!.value.isInitialized;
    if (controllerInitialized) {
      try {
        _startImageDataListening();
      } on CameraException catch (e) {
        _showCameraException(e);
      }
      _callControllerCreated();
      return cameraView;
    }
    return FutureBuilder<Widget>(future: () async {
      try {
        await _initController();
        _startImageDataListening();
      } on CameraException catch (e) {
        _showCameraException(e);
      }
      _callControllerCreated();
      return cameraView;
    }(), builder: (ctx, shot) {
      if (shot.connectionState == ConnectionState.done && shot.hasData) {
        return shot.data!;
      } else {
        return const Center(child: CircularProgressIndicator());
      }
    });
  }

  // Display the preview from the camera.
  Widget _cameraPreviewWidget(double cropSize) {
    widget.scannerOverlay ??= ScannerOverlay(
      borderColor: Theme.of(context).primaryColor,
      overlayColor: const Color.fromRGBO(0, 0, 0, 0.5),
      borderRadius: 1,
      borderLength: 16,
      borderWidth: 8,
      cutOutSize: cropSize,
    );
    widget.scannerOverlayWidget ??= Container(
      decoration: ShapeDecoration(
        shape: widget.scannerOverlay!,
      ),
    );

    final size = MediaQuery.of(context).size;
    var cameraMaxSize = max(size.width, size.height);
    return Stack(
      children: [
        SizedBox(
          width: cameraMaxSize,
          height: cameraMaxSize,
          child: ClipRRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cameraMaxSize,
                  child: CameraPreview(widget.controller!),
                ),
              ),
            ),
          ),
        ),
        widget.showCroppingRect ? widget.scannerOverlayWidget! : Container()
      ],
    );
  }
}
