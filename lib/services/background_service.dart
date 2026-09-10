import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

/// Canal de notificación del servicio. Lo crea MainActivity.kt al abrir la app
/// (Android 8+ exige que exista antes de startForeground; si no, la app se cierra).
const String kCanalRastreo = 'vendu_location_channel';

/// Tabla donde la app deja las posiciones. El dashboard las lee a través de la
/// vista `vista_ultima_posicion` / `vista_recorrido_hoy` (SQL 06).
const String kTablaUbicaciones = 'ubicaciones_motorizados';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: kCanalRastreo,
      initialNotificationTitle: 'Vendu Motorizados',
      initialNotificationContent: 'Rastreo de ruta activo',
      foregroundServiceNotificationId: 888,
      // Android 14+ exige declarar el tipo del servicio en primer plano; el
      // AndroidManifest ya lo declara como "location", esto lo pasa al plugin.
      foregroundServiceTypes: [AndroidForegroundType.location],
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

  // Cualquier error de arranque se reporta a la app en vez de tumbar el servicio.
  void reportar(String mensaje) {
    debugPrint('[rastreo] $mensaje');
    service.invoke('trackingError', {'mensaje': mensaje});
  }

  Box? offlineBox;
  try {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);
    offlineBox = await Hive.openBox('ubicaciones_offline');
  } catch (e) {
    reportar('No se pudo abrir la cola offline: $e');
  }

  SupabaseClient? supabase;
  try {
    // Este isolate es independiente del de la app: hay que inicializar Supabase
    // de nuevo. Recupera la sesión guardada del motorizado.
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabasePublishableKey,
    );
    supabase = Supabase.instance.client;
  } catch (e) {
    reportar('No se pudo conectar con Supabase en segundo plano: $e');
  }

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  StreamSubscription<Position>? sub;
  service.on('stopService').listen((event) {
    sub?.cancel();
    service.stopSelf();
  });

  // Una posición cada ~20 s o cada 15 m recorridos (lo que ocurra después),
  // para no llenar la base con miles de puntos idénticos en un semáforo.
  const LocationSettings ajustes = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 15,
    intervalDuration: Duration(seconds: 20),
  );

  int enviados = 0;

  sub = Geolocator.getPositionStream(locationSettings: ajustes).listen(
    (Position position) async {
      final user = supabase?.auth.currentUser;

      if (supabase != null && user != null) {
        final payload = {
          'user_id': user.id,
          'latitud': position.latitude,
          'longitud': position.longitude,
          'created_at': DateTime.now().toIso8601String(),
        };

        try {
          if (offlineBox != null && offlineBox.isNotEmpty) {
            final pendientes = <Map<String, dynamic>>[
              for (final key in offlineBox.keys)
                Map<String, dynamic>.from(offlineBox.get(key)),
            ];
            await supabase.from(kTablaUbicaciones).insert(pendientes);
            await offlineBox.clear();
            enviados += pendientes.length;
          }
          await supabase.from(kTablaUbicaciones).insert(payload);
          enviados++;
        } catch (e) {
          // Sin red, o sin permiso en la tabla (RLS): se guarda y se reintenta.
          await offlineBox?.add(payload);
          debugPrint('[rastreo] guardado offline (${offlineBox?.length ?? 0} pendientes): $e');
          if (e.toString().contains('42501') || e.toString().contains('permission')) {
            reportar('Supabase rechazó la posición (permisos). Avisa a la oficina.');
          }
        }
      } else if (supabase != null) {
        reportar('No hay sesión activa en segundo plano; vuelve a iniciar sesión.');
      }

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Vendu Motorizados · rastreo activo',
          content:
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} · $enviados enviadas',
        );
      }

      service.invoke('updateLocation', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'enviados': enviados,
        'pendientes': offlineBox?.length ?? 0,
      });
    },
    onError: (Object e) {
      reportar('Error del GPS: $e');
    },
  );
}
