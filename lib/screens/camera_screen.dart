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
  int frameCount = 0;

  final int inputSize = 640;
  final int numClasses = 80;

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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
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
      print("❌ Error inicializando cámara: $e");
    }
  }

  Future<void> _loadModel() async {
    try {
      final options = tfl.InterpreterOptions()..threads = 4;
      _interpreter = await tfl.Interpreter.fromAsset(
        "assets/models/yolov8n_float32.tflite",
        options: options,
      );

      setState(() {
        debugMessage = "✅ Modelo cargado";
      });
      print("✅ Modelo YOLOv8 cargado. Tamaño de entrada: $inputSize x $inputSize");
    } catch (e) {
      setState(() {
        debugMessage = "❌ Error cargando modelo: $e";
      });
      print("❌ Error cargando modelo: $e");
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
      frameCount++;
      if (frameCount % 10 != 0) return;

      if (!isDetecting) {
        isDetecting = true;
        print("🖼️ Procesando frame #$frameCount");
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

      final inputImage = _convertCameraImage(image);
      final inputBuffer = _preprocessImage(inputImage);

      final outputShape = [1, 84, 8400];
      final outputBuffer = List.generate(
          outputShape[0],
          (_) => List.generate(
              outputShape[1],
              (_) => List<double>.filled(outputShape[2], 0.0)));

      Map<int, Object> outputs = {0: outputBuffer};

      _interpreter?.runForMultipleInputs([inputBuffer], outputs);

      final output = outputs[0] as List<List<List<double>>>;
      print("📤 Output shape: ${output.length}x${output[0].length}x${output[0][0].length}");

      _processYOLOv8Detections(output);
    } catch (e) {
      setState(() {
        debugMessage = "❌ Error procesando frame: $e";
      });
      print("❌ Error procesando frame: $e");
    }
  }

  List<List<List<double>>> _preprocessImage(img.Image image) {
    final inputTensor = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (_) => List<double>.filled(inputSize * 3, 0),
      ),
    );

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);

        inputTensor[0][y][x * 3] = img.getRed(pixel) / 255.0;
        inputTensor[0][y][x * 3 + 1] = img.getGreen(pixel) / 255.0;
        inputTensor[0][y][x * 3 + 2] = img.getBlue(pixel) / 255.0;
      }
    }

    return inputTensor;
  }

  void _processYOLOv8Detections(List<List<List<double>>> output) {
    print("📦 Procesando YOLOv8 detecciones...");
  }

  img.Image _convertCameraImage(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yBuffer = image.planes[0].bytes;

    final rgbBuffer = Uint8List(width * height * 3);
    int rgbIndex = 0;

    for (int i = 0; i < yBuffer.length; i++) {
      rgbBuffer[rgbIndex++] = yBuffer[i];
      rgbBuffer[rgbIndex++] = yBuffer[i];
      rgbBuffer[rgbIndex++] = yBuffer[i];
    }

    final rgbImage = img.Image.fromBytes(width, height, rgbBuffer);
    return img.copyResize(img.copyRotate(rgbImage, 90), width: inputSize, height: inputSize);
  }

  @override
  void dispose() {
    _interpreter?.close();
    _cameraController?.dispose();
    textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detector de Placas')),
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? Center(child: CircularProgressIndicator())
          : CameraPreview(_cameraController!),
    );
  }
}
