import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'theme/theme.dart';
import 'services/gps_service.dart';
import 'services/background_service.dart';
import 'services/map_service.dart';
import 'screens/login_screen.dart';
import 'screens/confirmar_entrega_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabasePublishableKey,
  );

  await initializeBackgroundService();

  runApp(const VenduApp());
}

class VenduApp extends StatelessWidget {
  const VenduApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vendu · Motorizados',
      debugShowCheckedModeBanner: false,
      theme: venduTheme(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: VenduColors.amarillo,
              ),
            ),
          );
        }

        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GpsService _gpsService = GpsService();
  final _supabase = Supabase.instance.client;

  bool _isTracking = false;
  bool _isLoadingParadas = true;

  // Motivo visible cuando la lista sale vacía (portado de vendu_service.dart).
  // Antes todos los fallos mostraban el mismo texto y no se podía diagnosticar.
  String? _motivo;

  List<Map<String, dynamic>> _paradas = [];

  double? _latitude;
  double? _longitude;

  // Canal Realtime: cuando el dashboard asigna/cambia una parada de este
  // motorizado, Supabase avisa y la lista se recarga sola.
  RealtimeChannel? _canalParadas;

  @override
  void initState() {
    super.initState();

    _checkServiceStatus();
    _cargarParadas();
    _suscribirRealtime();

    FlutterBackgroundService().on('updateLocation').listen((event) {
      if (mounted && event != null) {
        setState(() {
          _latitude = event['latitude'];
          _longitude = event['longitude'];
          _isTracking = true;
        });
      }
    });

    // El servicio avisa aquí si algo falla en segundo plano (permisos,
    // sesión, Supabase) en vez de cerrarse en silencio.
    FlutterBackgroundService().on('trackingError').listen((event) {
      if (mounted && event != null && event['mensaje'] != null) {
        _avisarRastreo(event['mensaje'].toString());
      }
    });
  }

  @override
  void dispose() {
    _canalParadas?.unsubscribe();
    super.dispose();
  }

  // ==========================================================
  // REALTIME: escuchar rutas_paradas del motorizado logueado
  // Requiere: ALTER PUBLICATION supabase_realtime ADD TABLE rutas_paradas
  // ==========================================================

  void _suscribirRealtime() {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    _canalParadas = _supabase
        .channel('rutas_paradas_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rutas_paradas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'motorizado_id',
            value: uid,
          ),
          callback: (_) {
            if (mounted) _cargarParadas();
          },
        )
        .subscribe();
  }

  // ==========================================================
  // CARGAR PARADAS DESDE SUPABASE
  // ==========================================================

  Future<void> _cargarParadas() async {
  try {
    if (mounted) {
      setState(() {
        _isLoadingParadas = true;
      });
    }

    final user = _supabase.auth.currentUser;

    debugPrint('========================================');
    debugPrint('CARGANDO PARADAS');
    debugPrint('Usuario autenticado: ${user != null}');
    debugPrint('Auth User ID: ${user?.id}');
    debugPrint('Email: ${user?.email}');
    debugPrint('========================================');

    if (user == null) {
      debugPrint('ERROR: NO HAY USUARIO AUTENTICADO');

      if (mounted) {
        setState(() {
          _paradas = [];
          _motivo = 'No hay sesión activa. Cierra sesión y vuelve a entrar.';
          _isLoadingParadas = false;
        });
      }

      return;
    }

    // ==========================================================
    // 1. BUSCAR EL MOTORIZADO CORRESPONDIENTE AL USUARIO
    // ==========================================================

    final motorizado = await _supabase
        .from('motorizados')
        .select('id, nombre, auth_user_id, activo, email')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    debugPrint('========================================');
    debugPrint('MOTORIZADO ENCONTRADO');
    debugPrint('$motorizado');
    debugPrint('========================================');

    if (motorizado == null) {
      debugPrint(
        'ERROR: NO EXISTE UN MOTORIZADO ASOCIADO AL USUARIO ${user.id}',
      );

      if (mounted) {
        setState(() {
          _paradas = [];
          _motivo =
              'Tu usuario (${user.email ?? user.id}) no está vinculado a un motorizado. '
              'Pide a la oficina que lo cree en la tabla motorizados.';
          _isLoadingParadas = false;
        });
      }

      return;
    }

    // ==========================================================
    // 2. VERIFICAR QUE EL MOTORIZADO ESTÉ ACTIVO
    // ==========================================================

    final activo = motorizado['activo'] == true;

    if (!activo) {
      debugPrint('ERROR: EL MOTORIZADO ESTÁ INACTIVO');

      if (mounted) {
        setState(() {
          _paradas = [];
          _motivo =
              '${motorizado['nombre'] ?? 'Tu perfil'} está marcado como inactivo. '
              'La oficina debe activarlo en la tabla motorizados.';
          _isLoadingParadas = false;
        });
      }

      return;
    }

    // rutas_paradas.motorizado_id es UUID y coincide con auth.users.id.
    final motorizadoId = motorizado['auth_user_id'] as String?;

    if (motorizadoId == null || motorizadoId.isEmpty) {
      debugPrint('ERROR: EL MOTORIZADO NO TIENE auth_user_id');
      if (mounted) {
        setState(() {
          _paradas = [];
          _motivo = 'Tu perfil de motorizado no tiene un ID de autenticación válido.';
          _isLoadingParadas = false;
        });
      }
      return;
    }

    debugPrint('========================================');
    debugPrint('MOTORIZADO ID: $motorizadoId');
    debugPrint('========================================');

    // ==========================================================
    // 3. BUSCAR LAS PARADAS DEL MOTORIZADO
    // ==========================================================

    // La columna fecha del puente se genera en horario America/Caracas.
    // Calculamos la misma fecha para no depender de la zona horaria del teléfono.
    final hoyCaracas = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 4));
    final hoy = hoyCaracas.toIso8601String().split('T').first;

    final data = await _supabase
        .from('rutas_paradas')
        .select()
        .eq('motorizado_id', motorizadoId)
        .eq('fecha', hoy)
        .order('orden', ascending: true);

    debugPrint('========================================');
    debugPrint('RESULTADO SUPABASE');
    debugPrint('Motorizado ID: $motorizadoId');
    debugPrint('Cantidad de paradas: ${data.length}');
    debugPrint('Datos recibidos: $data');
    debugPrint('========================================');

    final paradasList =
        List<Map<String, dynamic>>.from(data);

    if (mounted) {
      setState(() {
        _paradas = paradasList;
        _motivo = paradasList.isEmpty
            ? '${motorizado['nombre'] ?? 'Este motorizado'} no tiene paradas '
                'asignadas para hoy ($hoy). Asígnalas desde el dashboard.'
            : null;
        _isLoadingParadas = false;
      });

      await _evaluarRastreoAutomatico(paradasList);
    }
  } catch (e, stackTrace) {
    debugPrint('========================================');
    debugPrint('ERROR CARGANDO PARADAS');
    debugPrint('ERROR: $e');
    debugPrint('STACK TRACE: $stackTrace');
    debugPrint('========================================');

    if (mounted) {
      setState(() {
        _paradas = [];
        // Un "permission denied" (42501) o RLS mal configurada aparece aquí,
        // en vez de disfrazarse de "no tienes paradas".
        _motivo = 'Error al consultar Supabase: $e';
        _isLoadingParadas = false;
      });
    }
  }
}

  // ==========================================================
  // EVALUAR RASTREO AUTOMÁTICO
  // ==========================================================

  Future<void> _evaluarRastreoAutomatico(
    List<Map<String, dynamic>> paradas,
  ) async {
    if (paradas.isEmpty) return;

    final completadas =
        paradas.where((p) => p['estado'] == 'completada').length;
    final total = paradas.length;
    final pendientes = total - completadas;

    // Antes solo arrancaba tras completar la PRIMERA parada, así que el
    // trayecto oficina → primera máquina nunca quedaba registrado. Ahora
    // arranca en cuanto hay paradas pendientes y se detiene al terminar todas.
    if (pendientes > 0) {
      await _iniciarRastreo(silencioso: true);
    } else if (completadas == total && total > 0) {
      await _detenerRastreo();
    }
  }

  // ==========================================================
  // INICIAR / DETENER RASTREO (botón y automático)
  // ==========================================================

  Future<void> _iniciarRastreo({bool silencioso = false}) async {
    final service = FlutterBackgroundService();
    try {
      if (await service.isRunning()) {
        if (mounted) setState(() => _isTracking = true);
        return;
      }

      // 1) Ubicación (obligatoria)
      final tieneUbicacion = await _gpsService.requestAllPermissions();
      if (!tieneUbicacion) {
        _avisarRastreo(
          'Sin permiso de ubicación. Actívalo en Ajustes → Aplicaciones → Vendu → Permisos.',
          silencioso: silencioso,
        );
        return;
      }

      // 2) Notificaciones (Android 13+): el servicio muestra una notificación
      //    permanente; sin este permiso Android puede negarse a arrancarlo.
      final notif = await Permission.notification.status;
      if (notif.isDenied) {
        await Permission.notification.request();
      }

      // 3) Ubicación "todo el tiempo" (opcional, mejora el rastreo con la
      //    pantalla apagada). Si el chofer la niega, igual funciona en primer plano.
      final siempre = await Permission.locationAlways.status;
      if (siempre.isDenied) {
        await Permission.locationAlways.request();
      }

      final started = await service.startService();
      if (mounted) setState(() => _isTracking = started);
      if (!started) {
        _avisarRastreo('Android no dejó arrancar el rastreo. Revisa los permisos de la app.',
            silencioso: silencioso);
      }
    } catch (e) {
      // Nunca dejar que un fallo del servicio tumbe la pantalla.
      if (mounted) setState(() => _isTracking = false);
      _avisarRastreo('No se pudo iniciar el rastreo: $e', silencioso: silencioso);
    }
  }

  Future<void> _detenerRastreo() async {
    final service = FlutterBackgroundService();
    try {
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isTracking = false;
        _latitude = null;
        _longitude = null;
      });
    }
  }

  void _avisarRastreo(String texto, {bool silencioso = false}) {
    debugPrint('[rastreo] $texto');
    if (silencioso || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: VenduColors.rojo),
    );
  }

  // ==========================================================
  // ESTADO DEL SERVICIO GPS
  // ==========================================================

  Future<void> _checkServiceStatus() async {
    final isRunning =
        await FlutterBackgroundService().isRunning();

    if (mounted) {
      setState(() {
        _isTracking = isRunning;
      });
    }
  }

  // ==========================================================
  // CERRAR SESIÓN
  // ==========================================================

  Future<void> _logout() async {
    final service = FlutterBackgroundService();

    if (await service.isRunning()) {
      service.invoke('stopService');
    }

    await _supabase.auth.signOut();
  }

  // ==========================================================
  // OPCIONES DE NAVEGACIÓN
  // ==========================================================

  void _mostrarOpcionesNavegacion(
    Map<String, dynamic> parada,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VenduColors.negroSuave,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12),
        ),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 20,
            horizontal: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IR A: ${(parada['nombre_cliente'] ?? 'PARADA').toString().toUpperCase()}',
                style: const TextStyle(
                  color: VenduColors.gris,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),

              // GOOGLE MAPS
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VenduColors.amarillo.withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.map,
                    color: VenduColors.amarillo,
                  ),
                ),
                title: const Text(
                  'Google Maps',
                  style: TextStyle(
                    color: VenduColors.blanco,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);

                  await _lanzarNavegacion(
                    'google',
                    parada,
                  );
                },
              ),

              const Divider(
                color: VenduColors.borde,
              ),

              // WAZE
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VenduColors.amarillo.withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.navigation,
                    color: VenduColors.amarillo,
                  ),
                ),
                title: const Text(
                  'Waze',
                  style: TextStyle(
                    color: VenduColors.blanco,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);

                  await _lanzarNavegacion(
                    'waze',
                    parada,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // ABRIR NAVEGACIÓN
  // ==========================================================

  Future<void> _lanzarNavegacion(
    String app,
    Map<String, dynamic> parada,
  ) async {
    final double? lat = parada['latitud'] != null
        ? double.tryParse(
            parada['latitud'].toString(),
          )
        : null;

    final double? lng = parada['longitud'] != null
        ? double.tryParse(
            parada['longitud'].toString(),
          )
        : null;

    try {
      await MapService.abrirNavegacion(
        app: app,
        lat: lat,
        lng: lng,
        direccion: parada['direccion'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: VenduColors.rojo,
          ),
        );
      }
    }
  }

  // ==========================================================
  // INTERFAZ
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'VENDU LOGÍSTICA',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout,
              color: VenduColors.gris,
            ),
            onPressed: _logout,
            tooltip: 'Cerrar Sesión',
          ),
        ],
      ),

      // ======================================================
      // CONTENIDO
      // ======================================================

      body: RefreshIndicator(
        color: VenduColors.amarillo,
        backgroundColor: VenduColors.negroSuave,
        onRefresh: _cargarParadas,

        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [

              // ==================================================
              // ESTADO DEL RASTREO
              // ==================================================

              Card(
                color: VenduColors.negroSuave,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(8),
                  side: BorderSide(
                    color: _isTracking
                        ? VenduColors.amarillo
                        : VenduColors.borde,
                    width:
                        _isTracking ? 1.5 : 1.0,
                  ),
                ),

                child: Padding(
                  padding:
                      const EdgeInsets.all(16.0),

                  child: Row(
                    children: [

                      Container(
                        padding:
                            const EdgeInsets.all(10),

                        decoration:
                            BoxDecoration(
                          color: _isTracking
                              ? VenduColors.amarillo
                                  .withValues(
                                    alpha: 0.15,
                                  )
                              : VenduColors.borde,
                          borderRadius:
                              BorderRadius.circular(8),
                        ),

                        child: Icon(
                          Icons.two_wheeler,
                          size: 28,
                          color: _isTracking
                              ? VenduColors.amarillo
                              : VenduColors.gris,
                        ),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [

                            Text(
                              _isTracking
                                  ? 'RASTREO ACTIVO'
                                  : 'RASTREO INACTIVO',

                              style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    FontWeight.bold,
                                letterSpacing: 0.8,
                                color: _isTracking
                                    ? VenduColors.amarillo
                                    : VenduColors.blanco,
                              ),
                            ),

                            const SizedBox(height: 4),

                            if (_latitude != null &&
                                _longitude != null)

                              Text(
                                'Lat: ${_latitude!.toStringAsFixed(4)} | Lng: ${_longitude!.toStringAsFixed(4)}',

                                style:
                                    const TextStyle(
                                  fontSize: 12,
                                  color:
                                      VenduColors.gris,
                                  fontFamily:
                                      'monospace',
                                ),
                              )

                            else if (_isTracking)

                              const Text(
                                'Obteniendo señal GPS...',

                                style:
                                    TextStyle(
                                  fontSize: 12,
                                  color:
                                      VenduColors.gris,
                                ),
                              )

                            else

                              const Text(
                                'Arranca solo cuando hay paradas pendientes',

                                style:
                                    TextStyle(
                                  fontSize: 12,
                                  color:
                                      VenduColors.gris,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Botón manual: permite arrancar/detener sin depender
                      // del estado de las paradas (y probar el GPS).
                      TextButton(
                        onPressed: () => _isTracking
                            ? _detenerRastreo()
                            : _iniciarRastreo(),
                        style: TextButton.styleFrom(
                          foregroundColor: _isTracking
                              ? VenduColors.gris
                              : VenduColors.amarillo,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                        ),
                        child: Text(
                          _isTracking ? 'Detener' : 'Iniciar',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ==================================================
              // TÍTULO PARADAS
              // ==================================================

              Row(
                children: [

                  Container(
                    width: 4,
                    height: 18,
                    color: VenduColors.amarillo,
                  ),

                  const SizedBox(width: 8),

                  const Text(
                    'Paradas Asignadas',

                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          VenduColors.blanco,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ==================================================
              // CARGANDO
              // ==================================================

              if (_isLoadingParadas)

                const Padding(
                  padding:
                      EdgeInsets.symmetric(
                    vertical: 30,
                  ),

                  child: Center(
                    child:
                        CircularProgressIndicator(
                      color:
                          VenduColors.amarillo,
                    ),
                  ),
                )

              // ==================================================
              // SIN PARADAS
              // ==================================================

              else if (_paradas.isEmpty)

                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 30,
                    horizontal: 8,
                  ),

                  child: Center(
                    child: Text(
                      _motivo ??
                          'No tienes paradas asignadas para hoy.',
                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        color:
                            VenduColors.gris,
                        height: 1.4,
                      ),
                    ),
                  ),
                )

              // ==================================================
              // PARADAS
              // ==================================================

              else

                ListView.builder(
                  shrinkWrap: true,

                  physics:
                      const NeverScrollableScrollPhysics(),

                  itemCount:
                      _paradas.length,

                  itemBuilder:
                      (context, index) {

                    final parada =
                        _paradas[index];

                    final esCompletada =
                        parada['estado'] ==
                            'completada';

                    return Card(
                      margin:
                          const EdgeInsets.only(
                        bottom: 8,
                      ),

                      child: ListTile(
                        contentPadding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),

                        onTap: () =>
                            _mostrarOpcionesNavegacion(
                          parada,
                        ),

                        // ========================================
                        // ICONO DE PARADA
                        // ========================================

                        leading: Container(
                          width: 32,
                          height: 32,

                          decoration:
                              BoxDecoration(
                            color: esCompletada
                                ? VenduColors
                                    .verde
                                    .withValues(
                                      alpha: 0.2,
                                    )
                                : VenduColors
                                    .amarillo
                                    .withValues(
                                      alpha: 0.15,
                                    ),

                            borderRadius:
                                BorderRadius
                                    .circular(6),
                          ),

                          child: Icon(
                            esCompletada
                                ? Icons.check
                                : Icons
                                    .navigation_outlined,

                            size: 18,

                            color: esCompletada
                                ? VenduColors
                                    .verde
                                : VenduColors
                                    .amarillo,
                          ),
                        ),

                        // ========================================
                        // CLIENTE
                        // ========================================

                        title: Text(
                          parada[
                                  'nombre_cliente'] ??
                              'Ubicación',

                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 15,
                            color:
                                VenduColors
                                    .blanco,
                          ),
                        ),

                        // ========================================
                        // DIRECCIÓN
                        // ========================================

                        subtitle: Text(
                          parada[
                                  'direccion'] ??
                              '',

                          style:
                              const TextStyle(
                            color:
                                VenduColors
                                    .gris,
                            fontSize: 13,
                          ),
                        ),

                        // ========================================
                        // BOTÓN DE ENTREGA
                        // ========================================

                        trailing:
                            esCompletada

                                ? Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),

                                    decoration:
                                        BoxDecoration(
                                      color: VenduColors
                                          .verde
                                          .withValues(
                                        alpha: 0.15,
                                      ),

                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        4,
                                      ),

                                      border:
                                          Border.all(
                                        color:
                                            VenduColors
                                                .verde,
                                        width: 1,
                                      ),
                                    ),

                                    child:
                                        const Text(
                                      'COMPLETADA',

                                      style:
                                          TextStyle(
                                        fontSize: 10,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                        color:
                                            VenduColors
                                                .verde,
                                      ),
                                    ),
                                  )

                                : Container(
                                    decoration:
                                        BoxDecoration(
                                      color:
                                          VenduColors
                                              .amarillo,

                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        6,
                                      ),
                                    ),

                                    child:
                                        IconButton(
                                      icon:
                                          const Icon(
                                        Icons
                                            .camera_alt,
                                        color:
                                            VenduColors
                                                .negro,
                                        size: 20,
                                      ),

                                      tooltip:
                                          'Registrar entrega',

                                      onPressed:
                                          () async {

                                        final result =
                                            await Navigator
                                                .push(
                                          context,

                                          MaterialPageRoute(
                                            builder:
                                                (context) =>
                                                    ConfirmarEntregaScreen(
                                              paradaId:
                                                  parada[
                                                          'id']
                                                      .toString(),
                                            ),
                                          ),
                                        );

                                        if (result ==
                                            true) {
                                          _cargarParadas();
                                        }
                                      },
                                    ),
                                  ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}