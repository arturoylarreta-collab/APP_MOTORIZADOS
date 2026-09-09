// lib/utils/map_helper.dart
import 'package:url_launcher/url_launcher.dart';

Future<void> abrirEnGoogleMaps({
  double? latitud,
  double? longitud,
  String? direccion,
}) async {
  Uri uri;

  if (latitud != null && longitud != null) {
    uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitud,$longitud');
  } else if (direccion != null && direccion.isNotEmpty) {
    final query = Uri.encodeComponent(direccion);
    uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
  } else {
    return;
  }

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}