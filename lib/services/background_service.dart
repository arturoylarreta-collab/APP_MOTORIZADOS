import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'vendu_location_channel',
      initialNotificationTitle: 'Vendu Motorizados',
      initialNotificationContent: 'Rastreo de ruta activo',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);
  final Box offlineBox = await Hive.openBox('ubicaciones_offline');

  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabasePublishableKey,
  );

  final supabase = Supabase.instance.client;

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  ).listen((Position position) async {
    final user = supabase.auth.currentUser;

    if (user != null) {
      final payload = {
        'user_id': user.id,
        'latitud': position.latitude,
        'longitud': position.longitude,
        'created_at': DateTime.now().toIso8601String(),
      };

      try {
        if (offlineBox.isNotEmpty) {
          final List<Map<String, dynamic>> pendingItems = [];
          for (var key in offlineBox.keys) {
            final item = Map<String, dynamic>.from(offlineBox.get(key));
            pendingItems.add(item);
          }

          await supabase.from('ubicaciones_motorizados').insert(pendingItems);
          await offlineBox.clear();
        }

        await supabase.from('ubicaciones_motorizados').insert(payload);
      } catch (e) {
        await offlineBox.add(payload);
        debugPrint('Guardado offline en Hive (Total pendientes: ${offlineBox.length})');
      }
    }

    service.invoke('updateLocation', {
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
  });
}