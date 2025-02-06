import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert'; // Asegúrate de que esta línea esté presente


class PursuitModeScreen extends StatefulWidget {
  final String plate; // La placa en modo persecución

  const PursuitModeScreen({Key? key, required this.plate}) : super(key: key);

  @override
  _PursuitModeScreenState createState() => _PursuitModeScreenState();
}

class _PursuitModeScreenState extends State<PursuitModeScreen> {
  List<CameraDescription> cameras = [];
  CameraController? controller;
  Timer? timer;
  bool isPursuitActive = true;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startPursuitMode();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      controller = CameraController(cameras[0], ResolutionPreset.medium);
      await controller?.initialize();
      setState(() {});
    }
  }

  void _startPursuitMode() {
    timer = Timer.periodic(Duration(seconds: 1), (_) => _processFrame());
  }

  void _stopPursuitMode() {
    timer?.cancel();
    timer = null;
    setState(() {
      isPursuitActive = false;
    });
  }

  Future<void> _processFrame() async {
    if (isProcessing || controller == null || !controller!.value.isInitialized) return;

    isProcessing = true;
    try {
      final frame = await controller!.takePicture();
      final bytes = await frame.readAsBytes();

      // Envía el cuadro al backend y verifica la placa
      final detectedPlate = await _sendFrameToBackend(bytes);

      if (detectedPlate != null && detectedPlate == widget.plate) {
        print("Placa en modo persecución detectada: ${widget.plate}");
        _showPursuitAlert();
      }
    } catch (e) {
      print("Error al procesar el cuadro: $e");
    } finally {
      isProcessing = false;
    }
  }

  Future<String?> _sendFrameToBackend(Uint8List frameBytes) async {
    final uri = Uri.parse("http://172.20.10.5:5000/process-image");
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'image',
            frameBytes,
            filename: 'frame.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final data = json.decode(responseData);
        final vehicles = data['data']['vehicles'];
        if (vehicles.isNotEmpty && vehicles[0]['plate']['found']) {
          return vehicles[0]['plate']['unicodeText'];
        }
      } else {
        print("Error en el servidor: ${response.statusCode}");
      }
    } catch (e) {
      print("Error al conectar con el backend: $e");
    }
    return null;
  }

  void _showPursuitAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Placa Detectada"),
        content: Text("Placa ${widget.plate} encontrada en modo persecución."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Modo Persecución"),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Modo Persecución"),
        actions: [
          IconButton(
            icon: Icon(Icons.stop),
            onPressed: () {
              _stopPursuitMode();
              Navigator.pop(context); // Volver a la pantalla anterior
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(controller!),
          if (isPursuitActive)
            Positioned.fill(
              child: Container(
                color: Colors.red.withOpacity(0.2), // Efecto visual de sirena
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopPursuitMode();
    controller?.dispose();
    super.dispose();
  }
}