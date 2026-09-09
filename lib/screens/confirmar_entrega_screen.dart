// lib/screens/confirmar_entrega_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gps_service.dart';

class ConfirmarEntregaScreen extends StatefulWidget {
  final String? paradaId; // Opcional, si está vinculado a una parada específica

  const ConfirmarEntregaScreen({super.key, this.paradaId});

  @override
  State<ConfirmarEntregaScreen> createState() => _ConfirmarEntregaScreenState();
}

class _ConfirmarEntregaScreenState extends State<ConfirmarEntregaScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _observacionesController = TextEditingController();
  final GpsService _gpsService = GpsService();
  final _supabase = Supabase.instance.client;

  File? _imageFile;
  bool _isUploading = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacionActual();
  }

  // Obtiene la ubicación GPS exacta del momento del reporte
  Future<void> _obtenerUbicacionActual() async {
    try {
      final pos = await _gpsService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    } catch (e) {
      debugPrint('Error al obtener ubicación puntual: $e');
    }
  }

  // Captura la foto usando la cámara
  Future<void> _tomarFoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70, // Comprime la imagen para ahorrar datos móviles
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (photo != null) {
        setState(() {
          _imageFile = File(photo.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir la cámara: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Proceso de subida de foto y guardado en Supabase
  Future<void> _guardarReporte() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, toma una foto como evidencia.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesión no encontrada');

      // 1. Nombre único para el archivo de imagen
      final String fileName =
          '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = 'entregas/$fileName';

      // 2. Subir imagen a Supabase Storage
      await _supabase.storage.from('evidencias').upload(
            filePath,
            _imageFile!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // 3. Obtener URL pública de la imagen
      final String publicUrl =
          _supabase.storage.from('evidencias').getPublicUrl(filePath);

      // 4. Guardar registro en la base de datos Supabase
      await _supabase.from('evidencias_entregas').insert({
        'user_id': userId,
        'parada_id': widget.paradaId,
        'foto_url': publicUrl,
        'observaciones': _observacionesController.text.trim(),
        'latitud': _currentPosition?.latitude,
        'longitud': _currentPosition?.longitude,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Evidencia de entrega registrada con éxito!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Retorna 'true' para actualizar la vista previa
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar reporte: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar Entrega / Parada'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Vista previa de la Foto
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: _imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _imageFile!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 60, color: Colors.grey),
                        SizedBox(height: 10),
                        Text('Sin foto capturada',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // Botón Tomar / Repetir Foto
            OutlinedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.photo_camera),
              label: Text(_imageFile == null ? 'Tomar Foto' : 'Cambiar Foto'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Campo de Observaciones
            TextField(
              controller: _observacionesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones / Notas',
                hintText: 'Ej. Se entregó mercancía a recepción. Todo en orden.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Indicador GPS Puntual
            Row(
              children: [
                Icon(
                  Icons.my_location,
                  size: 18,
                  color: _currentPosition != null ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentPosition != null
                      ? 'Ubicación GPS registrada'
                      : 'Obteniendo GPS...',
                  style: TextStyle(
                    fontSize: 13,
                    color: _currentPosition != null ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // Botón Guardar / Enviar
            ElevatedButton(
              onPressed: _isUploading ? null : _guardarReporte,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isUploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Guardar Evidencia',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}