import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrackingService {
  static final _supabase = Supabase.instance.client;

  /// Solicita permisos y valida estado del GPS
  static Future<bool> _validarPermisos() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    
    return permission != LocationPermission.deniedForever;
  }

  /// Transmite la ubicación cada vez que el motorizado se desplaza N metros
  static Future<void> iniciarRastreoContinuo(String motorizadoId) async {
    final tienePermiso = await _validarPermisos();
    if (!tienePermiso) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // Envía actualización cada 15 metros recorridos
    );

    Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) async {
        await _supabase.from('ubicaciones').insert({
          'motorizado_id': motorizadoId,
          'latitud': position.latitude,
          'longitud': position.longitude,
        });
      },
    );
  }
}