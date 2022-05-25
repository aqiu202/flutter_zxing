import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_beep/flutter_beep.dart';

import 'event_listener.dart';
import 'flutter_zxing.dart';

class ZXingCamera extends StatefulWidget {
  ZXingCamera(
      {Key? key,
      required this.onScan,
      this.onControllerCreated,
      this.codeFormat = Format.Any,
      this.beep = true,
      this.showCroppingRect = true,
      this.scanPeriod = const Duration(milliseconds: 200), // 200ms delay
      this.resolveDelay = const Duration(milliseconds: 800), // 800ms delay
      this.cropPercent = 0.6, // 60% of the screen
      this.resolution = ResolutionPreset.high,
      this.fullScreen = false,
      this.cameraController,
      this.scannerOverlayWidget,
      this.scannerOverlay})
      : super(key: key);

  static Future<void> init() async {
    cameras ??= await availableCameras();
  }

  static List<CameraDescription>? cameras;

  final Function(CodeResult) onScan;
  final Function(CameraController)? onControllerCreated;
  final int codeFormat;
  final bool beep;
  final bool showCroppingRect;
  final Duration scanPeriod;
  final Duration resolveDelay;
  final double cropPercent;
  final ResolutionPreset resolution;
  final bool fullScreen;
  Widget? scannerOverlayWidget;
  ScannerOverlay? scannerOverlay;
  CameraController? cameraController;

  @override
  State<ZXingCamera> createState() => _ZXingCameraState();
}

class _ZXingCameraState extends State<ZXingCamera>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;

  bool get isAndroid => Platform.isAndroid;

  // true when code detecting is ongoing
  bool _isProcessing = false;

  /// Instance of [EventListener]
  late EventListener eventListener;

  @override
  void initState() {
    super.initState();
    initStateAsync();
  }

  void initStateAsync() async {
    WidgetsBinding.instance.addObserver(this);
    controller = widget.cameraController;
    if (controller == null) {
      ZXingCamera.cameras ??= await availableCameras();
      setState((){
        _onNewCameraSelected(ZXingCamera.cameras!.first);
      });
    } else {
      controller?.startImageStream(_processCameraImage);
      widget.onControllerCreated?.call(controller!);
    }
    // Spawn a new isolate
    eventListener = EventListener();
    await eventListener.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _onNewCameraSelected(cameraController.description);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    eventListener.stop();
    super.dispose();
  }

  void _onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.dispose();
    }

    controller = CameraController(
      cameraDescription,
      widget.resolution,
      enableAudio: false,
      imageFormatGroup:
          isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );

    try {
      await controller?.initialize();
      controller?.startImageStream(_processCameraImage);
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    controller?.addListener(() {
      if (mounted) setState(() {});
    });

    if (mounted) {
      setState(() {});
    }
    widget.onControllerCreated?.call(controller!);
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void showInSnackBar(String message) {}

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
          setState(() {});
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
    return Stack(
      children: [
        // Camera preview
        Center(child: _cameraPreviewWidget(cropSize)),
      ],
    );
  }

  // Display the preview from the camera.
  Widget _cameraPreviewWidget(double cropSize) {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return const CircularProgressIndicator();
    } else {
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
                    child: CameraPreview(
                      cameraController,
                    ),
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
}
