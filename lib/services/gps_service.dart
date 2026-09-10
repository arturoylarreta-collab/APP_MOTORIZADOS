// lib/services/gps_service.dart
import 'package:geolocator/geolocator.dart';

class GpsService {
  Future<bool> requestAllPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    bool hasPermission = await requestAllPermissions();
    if (!hasPermission) return null;

    // `desiredAccuracy` desapareció en geolocator 13; `locationSettings`
    // funciona en todas las versiones desde la 10.
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}