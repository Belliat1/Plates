import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:image/image.dart' as img;
import 'package:google_ml_kit/google_ml_kit.dart';

class CameraScreen extends StatefulWidget {
  final List<String> plates;

  const CameraScreen({Key? key, required this.plates}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  tfl.Interpreter? _interpreter;
  bool isDetecting = false;
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  List<Map<String, dynamic>> _recognitions = [];
  String debugMessage = "📸 Iniciando...";

  final List<List<double>> anchors = [
    [1.08, 1.19], [3.42, 4.41], [6.63, 11.38],
    [9.42, 5.11], [16.62, 10.52]
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController?.initialize();
      if (mounted) {
        setState(() {
          debugMessage = "✅ Cámara lista";
        });
        _startDetection();
      }
    } catch (e) {
      setState(() {
        debugMessage = "❌ Error inicializando cámara: $e";
      });
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset("assets/models/yolov2_tiny.tflite");
      setState(() {
        debugMessage = "✅ Modelo cargado";
      });
    } catch (e) {
      setState(() {
        debugMessage = "❌ Error cargando modelo: $e";
      });
    }
  }

  void _startDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() {
        debugMessage = "❌ Cámara no lista";
      });
      return;
    }

    _cameraController?.startImageStream((CameraImage image) async {
      if (!isDetecting) {
        isDetecting = true;
        await _processFrame(image);
        isDetecting = false;
      }
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_interpreter == null) {
      setState(() {
        debugMessage = "❌ Modelo no cargado";
      });
      return;
    }

    try {
      setState(() {
        debugMessage = "📸 Procesando frame...";
      });

      img.Image inputImage = _convertCameraImage(image);
      Float32List input = _preprocessImage(inputImage);

      final outputShape = [1, 13, 13, 125];
      var output = List.filled(1 * 13 * 13 * 125, 0.0).reshape(outputShape);

      _interpreter?.run(input.buffer.asFloat32List(), output);

      _processDetections(output, image.width, image.height);
    } catch (e) {
      setState(() {
        debugMessage = "❌ Error procesando frame: $e";
      });
    }
  }

  img.Image _convertCameraImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final yRowStride = cameraImage.planes[0].bytesPerRow;
    final uvRowStride = cameraImage.planes[1].bytesPerRow;
    final uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    final image = img.Image(width: width, height: height);

    for (int h = 0; h < height; h++) {
      final int uvRow = uvRowStride * (h ~/ 2);
      final int yRow = yRowStride * h;

      for (int w = 0; w < width; w++) {
        final int uvIndex = uvRow + (w ~/ 2) * uvPixelStride;
        final int index = yRow + w;

        final yp = cameraImage.planes[0].bytes[index];
        final up = cameraImage.planes[1].bytes[uvIndex];
        final vp = cameraImage.planes[2].bytes[uvIndex];

        int r = (yp + (1.370705 * (vp - 128))).toInt().clamp(0, 255);
        int g = (yp - (0.337633 * (up - 128)) - (0.698001 * (vp - 128))).toInt().clamp(0, 255);
        int b = (yp + (1.732446 * (up - 128))).toInt().clamp(0, 255);

        image.setPixelRgb(w, h, r, g, b);
      }
    }

    return img.copyResize(img.copyRotate(image, 90), width: 416, height: 416);
  }

  Float32List _preprocessImage(img.Image image) {
    Float32List input = Float32List(416 * 416 * 3);
    int pixelIndex = 0;

    for (int y = 0; y < 416; y++) {
      for (int x = 0; x < 416; x++) {
        final pixel = image.getPixel(x, y);
        input[pixelIndex++] = img.getRed(pixel) / 255.0;
        input[pixelIndex++] = img.getGreen(pixel) / 255.0;
        input[pixelIndex++] = img.getBlue(pixel) / 255.0;
      }
    }
    return input;
  }

  void _processDetections(List output, int imageWidth, int imageHeight) {
    List<Map<String, dynamic>> results = [];

    for (int y = 0; y < 13; y++) {
      for (int x = 0; x < 13; x++) {
        for (int b = 0; b < 5; b++) {
          int index = (y * 13 + x) * 125 + b * 25;
          double confidence = _sigmoid(output[index + 4]);

          if (confidence > 0.3) {
            int classId = output.sublist(index + 5, index + 25).indexOf(output.sublist(index + 5, index + 25).reduce(max));
            String label = "Objeto $classId";

            double bx = (x + _sigmoid(output[index])) * (imageWidth / 13);
            double by = (y + _sigmoid(output[index + 1])) * (imageHeight / 13);
            double bw = exp(output[index + 2]) * anchors[b][0];
            double bh = exp(output[index + 3]) * anchors[b][1];

            results.add({"x": bx, "y": by, "w": bw, "h": bh, "confidence": confidence, "label": label});
          }
        }
      }
    }

    setState(() {
      _recognitions = results;
      debugMessage = "🔍 Detecciones: ${_recognitions.length}";
    });
  }

  double _sigmoid(double x) => 1 / (1 + exp(-x));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CameraPreview(_cameraController!),
    );
  }
}
