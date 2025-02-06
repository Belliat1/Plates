import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class CameraScreen extends StatefulWidget {
  final List<String> plates;

  const CameraScreen({Key? key, required this.plates}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  List<CameraDescription> cameras = [];
  CameraController? controller;
  bool isProcessing = false;
  Timer? timer;
  String detectedPlate = "";
  bool isPursuing = false;
  Database? database;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
    _initializeCamera();
  }

  Future<void> _initializeDatabase() async {
    database = await openDatabase(
      p.join(await getDatabasesPath(), 'plates.db'),
      onCreate: (db, version) {
        return db.execute("CREATE TABLE plates(id INTEGER PRIMARY KEY, plate TEXT UNIQUE)");
      },
      version: 1,
    );
  }

  Future<List<String>> _getPlatesFromDB() async {
    final db = database;
    if (db == null) return [];
    final List<Map<String, dynamic>> maps = await db.query('plates');
    return List.generate(maps.length, (i) => maps[i]['plate'] as String);
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final selectedCamera = await _selectCamera(context);
        if (selectedCamera != null) {
          controller = CameraController(selectedCamera, ResolutionPreset.high);
          await controller?.initialize();
          if (!mounted) return;
          setState(() {});
          _startProcessing();
        }
      } else {
        print("No hay cámaras disponibles.");
      }
    } catch (e) {
      print("Error inicializando cámara: $e");
    }
  }

  Future<CameraDescription?> _selectCamera(BuildContext context) async {
    return await showDialog<CameraDescription>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Selecciona una cámara"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: cameras.map((camera) {
              return ListTile(
                title: Text(camera.lensDirection.toString()),
                onTap: () => Navigator.pop(context, camera),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _startProcessing() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _processFrame());
  }

  Future<void> _processFrame() async {
    if (isProcessing || controller == null || !controller!.value.isInitialized) return;
    isProcessing = true;

    try {
      final frame = await controller!.takePicture();
      final bytes = await compute(_compressImage, await frame.readAsBytes());

      final detected = await _sendFrameToBackend(bytes);
      if (detected != null) {
        final plates = await _getPlatesFromDB();
        if (mounted) {
          setState(() {
            detectedPlate = detected;
            isPursuing = plates.contains(detected);
          });
        }
      }
    } catch (e) {
      print("Error procesando el fotograma: $e");
    }
    isProcessing = false;
  }

  static Future<Uint8List> _compressImage(Uint8List imageData) async {
    final codec = await ui.instantiateImageCodec(imageData, targetWidth: 640);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  Future<String?> _sendFrameToBackend(Uint8List frameBytes) async {
    final uri = Uri.parse("http://172.18.72.144:5000/video_feed");
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('video', frameBytes, filename: 'frame.jpg'));

      final response = await request.send();
      if (response.statusCode == 200) {
        final data = json.decode(await response.stream.bytesToString());
        return data['detections'].isNotEmpty ? data['detections'][0]['label'] : null;
      }
    } catch (e) {
      print("Error conectando con el backend: $e");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text("Cargando Cámara...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Detección de Placas")),
      body: Stack(
        children: [
          CameraPreview(controller!),
          if (detectedPlate.isNotEmpty)
            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                color: isPursuing ? Colors.red.withOpacity(0.7) : Colors.green.withOpacity(0.7),
                child: Column(
                  children: [
                    Text(
                      "Placa Detectada: $detectedPlate",
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
