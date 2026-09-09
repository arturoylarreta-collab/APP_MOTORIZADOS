// lib/services/map_service.dart
import 'package:url_launcher/url_launcher.dart';

class MapService {
  /// Abre Google Maps o Waze usando Coordenadas GPS o Dirección de texto como respaldo.
  static Future<void> abrirNavegacion({
    required String app, // 'google' o 'waze'
    double? lat,
    double? lng,
    String? direccion,
  }) async {
    Uri url;

    if (app == 'waze') {
      if (lat != null && lng != null) {
        url = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
      } else if (direccion != null && direccion.trim().isNotEmpty) {
        final query = Uri.encodeComponent(direccion);
        url = Uri.parse('https://waze.com/ul?q=$query&navigate=yes');
      } else {
        throw 'No hay ubicación ni dirección disponible para esta parada.';
      }
    } else {
      // Google Maps
      if (lat != null && lng != null) {
        url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      } else if (direccion != null && direccion.trim().isNotEmpty) {
        final query = Uri.encodeComponent(direccion);
        url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
      } else {
        throw 'No hay ubicación ni dirección disponible para esta parada.';
      }
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'No se pudo abrir $app en este dispositivo.';
    }
  }
}