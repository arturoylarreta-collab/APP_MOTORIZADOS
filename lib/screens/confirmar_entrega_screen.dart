// lib/screens/confirmar_entrega_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gps_service.dart';

class ConfirmarEntregaScreen extends StatefulWidget {
  final String? paradaId;

  const ConfirmarEntregaScreen({
    super.key,
    this.paradaId,
  });

  @override
  State<ConfirmarEntregaScreen> createState() =>
      _ConfirmarEntregaScreenState();
}

class _ConfirmarEntregaScreenState extends State<ConfirmarEntregaScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _observacionesController =
      TextEditingController();
  final GpsService _gpsService = GpsService();
  final _supabase = Supabase.instance.client;

  // Sin límite artificial: las fotos se acumulan hasta que el usuario
  // decide guardar la evidencia. El límite real es el almacenamiento/memoria
  // disponible del dispositivo.
  final List<XFile> _imageFiles = [];

  bool _isUploading = false;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacionActual();
  }

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

  // Toma una foto con la cámara y la agrega a la colección.
  Future<void> _tomarFoto() async {
    if (_isUploading) return;

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (photo != null && mounted) {
        setState(() {
          _imageFiles.add(photo);
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

  // Permite seleccionar varias imágenes existentes desde la galería.
  Future<void> _seleccionarGaleria() async {
    if (_isUploading) return;

    try {
      final List<XFile> photos = await _picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (photos.isNotEmpty && mounted) {
        setState(() {
          _imageFiles.addAll(photos);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imágenes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _eliminarFoto(int index) {
    if (_isUploading) return;

    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  Future<void> _guardarReporte() async {
    if (_imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, agrega al menos una foto como evidencia.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (widget.paradaId == null || widget.paradaId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta parada no tiene un ID válido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    final List<String> uploadedPaths = [];

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Sesión no encontrada');
      }

      // Una fila en evidencias_entregas por cada foto.
      // Esto permite múltiples fotos asociadas a la misma parada.
      for (int i = 0; i < _imageFiles.length; i++) {
        final image = _imageFiles[i];

        final fileName =
            '${userId}_${DateTime.now().microsecondsSinceEpoch}_$i.jpg';
        final filePath = 'entregas/$fileName';

        await _supabase.storage.from('evidencias').upload(
              filePath,
              File(image.path),
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );

        uploadedPaths.add(filePath);

        final publicUrl =
            _supabase.storage.from('evidencias').getPublicUrl(filePath);

        await _supabase.from('evidencias_entregas').insert({
          'user_id': userId,
          'parada_id': widget.paradaId,
          'foto_url': publicUrl,
          'observaciones': _observacionesController.text.trim(),
          'latitud': _currentPosition?.latitude,
          'longitud': _currentPosition?.longitude,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _imageFiles.length == 1
                  ? '¡Evidencia de entrega registrada con éxito!'
                  : '¡${_imageFiles.length} evidencias registradas con éxito!',
            ),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context, true);
      }
    } catch (e) {
      // Intentamos limpiar los archivos que sí alcanzaron a subir
      // si algún registro de la base de datos falla.
      if (uploadedPaths.isNotEmpty) {
        try {
          await _supabase.storage
              .from('evidencias')
              .remove(uploadedPaths);
        } catch (cleanupError) {
          debugPrint(
            'No se pudieron limpiar todas las fotos subidas: $cleanupError',
          );
        }
      }

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
            Text(
              _imageFiles.isEmpty
                  ? 'Evidencia fotográfica'
                  : '${_imageFiles.length} foto${_imageFiles.length == 1 ? '' : 's'} agregada${_imageFiles.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            if (_imageFiles.isEmpty)
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt,
                      size: 60,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Sin fotos capturadas',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _imageFiles.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final image = _imageFiles[index];

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(image.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                            tooltip: 'Eliminar foto',
                            onPressed: () => _eliminarFoto(index),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _tomarFoto,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Tomar foto'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _seleccionarGaleria,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _observacionesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones / Notas',
                hintText:
                    'Ej. Se entregó mercancía a recepción. Todo en orden.',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Icon(
                  Icons.my_location,
                  size: 18,
                  color:
                      _currentPosition != null ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentPosition != null
                      ? 'Ubicación GPS registrada'
                      : 'Obteniendo GPS...',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        _currentPosition != null ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

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
                  : Text(
                      _imageFiles.isEmpty
                          ? 'Agregar evidencia'
                          : 'Guardar ${_imageFiles.length} foto${_imageFiles.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
