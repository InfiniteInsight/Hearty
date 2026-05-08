import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/photo_type.dart';

/// The result returned by [CameraScreen] when the user captures a photo.
class CameraResult {
  final File file;
  final PhotoType preselectedType;

  const CameraResult({required this.file, required this.preselectedType});
}

/// A full-screen barcode scanner screen.
///
/// Automatically captures a photo when a barcode is detected and returns a
/// [CameraResult] via `Navigator.pop(result)`.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _permissionDenied = false;
  bool _isCapturing = false;
  bool _barcodeDetected = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;

      // Pick the first back-facing camera, fall back to first camera.
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
      });
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied') {
        setState(() => _permissionDenied = true);
      }
    } catch (_) {
      // Cameras unavailable; stay on loading state.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_barcodeDetected || _isCapturing) return;
    if (capture.barcodes.isEmpty) return;

    setState(() {
      _barcodeDetected = true;
      _isCapturing = true;
    });

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final xfile = await controller.takePicture();
      if (!mounted) return;
      final file = File(xfile.path);
      Navigator.of(context).pop(
        CameraResult(file: file, preselectedType: PhotoType.barcode),
      );
    } on CameraException catch (_) {
      if (mounted) {
        setState(() {
          _barcodeDetected = false;
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back button overlaid top-left.
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const Spacer(),
                _buildBottomToolbar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_permissionDenied) return _buildPermissionDeniedUI();
    if (!_isInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return MobileScanner(onDetect: _onBarcodeDetected);
  }

  Widget _buildPermissionDeniedUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Camera access is required to capture photos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _initCamera,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: Colors.black.withValues(alpha: 0.6),
      child: const Text(
        'Point camera at a barcode',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }
}
