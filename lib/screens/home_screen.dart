import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import 'camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _progress = 0.0;
  bool _isLoading = false;
  bool _fileUploaded = false;
  String _statusMessage = '';
  List<String> _plates = []; // Lista para almacenar las placas cargadas

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _progress = 0.0;
      _statusMessage = 'Cargando archivo...';
      _fileUploaded = false;
    });

    await Future.delayed(const Duration(seconds: 1));

    // Selecciona un archivo Excel o CSV
    final XTypeGroup typeGroup = XTypeGroup(
      label: 'Archivos de placas',
      extensions: ['csv', 'xlsx'],
    );

    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

    if (file != null) {
      final filePath = file.path;
      if (filePath.endsWith('.csv')) {
        await _readPlatesFromCsv(filePath);
      } else if (filePath.endsWith('.xlsx')) {
        await _readPlatesFromExcel(filePath);
      } else {
        setState(() {
          _statusMessage = 'Formato de archivo no compatible.';
        });
      }

      setState(() {
        _isLoading = false;
        _statusMessage = '¡Información cargada correctamente!';
        _fileUploaded = true;
      });

      print('Archivo seleccionado: $filePath');
    } else {
      setState(() {
        _isLoading = false;
        _statusMessage = 'No se seleccionó ningún archivo.';
      });
    }
  }

  Future<void> _readPlatesFromCsv(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      final csvTable = const CsvToListConverter().convert(content);

      setState(() {
        // Lee solo la primera columna y elimina encabezados
        _plates = csvTable.map((row) => row[0].toString().trim()).toList();
      });

      print("Placas cargadas desde CSV: $_plates");
    } catch (e) {
      print("Error al leer el archivo CSV: $e");
      setState(() {
        _statusMessage = 'Error al leer el archivo CSV.';
      });
    }
  }

  Future<void> _readPlatesFromExcel(String filePath) async {
    try {
      final bytes = File(filePath).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      setState(() {
        // Lee solo la primera columna de la primera hoja
        _plates = excel.tables.values.first.rows
            .map((row) => row.first.toString().trim())
            .toList();
      });

      print("Placas cargadas desde Excel: $_plates");
    } catch (e) {
      print("Error al leer el archivo Excel: $e");
      setState(() {
        _statusMessage = 'Error al leer el archivo Excel.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('V-Track-360'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '¡Bienvenido a V-Track-360!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'Tu herramienta inteligente para rastrear y gestionar placas de vehículos de manera eficiente.',
              style: TextStyle(fontSize: 16, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _fileUploaded
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CameraScreen(plates: _plates), // ✅ Ahora está definido correctamente
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: Colors.blue,
              ),
              child: const Text(
                '¡A rastrear!',
                style: TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _pickFile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: Colors.green,
              ),
              child: const Text(
                '¿Qué placas quieres rastrear?',
                style: TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              ...[
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey,
                  color: Colors.blue,
                ),
                const SizedBox(height: 10),
              ],
            if (_statusMessage.isNotEmpty)
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 40),
            const Text(
              'Desarrollado con 💙 por Provalia',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
