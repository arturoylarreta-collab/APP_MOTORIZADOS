import 'package:supabase_flutter/supabase_flutter.dart';

// ==========================================
// MODELOS DE DATOS
// ==========================================

class Motorizado {
  final int id;
  final String nombre;
  final String? email;

  Motorizado({required this.id, required this.nombre, this.email});

  factory Motorizado.fromMap(Map<String, dynamic> m) => Motorizado(
        id: (m['id'] as num).toInt(),
        nombre: (m['nombre'] ?? '') as String,
        email: m['email'] as String?,
      );
}

class Parada {
  final int id;
  final int orden;
  final String maquina;
  final String? direccion;
  final double? latitud;
  final double? longitud;
  String estado;

  Parada({
    required this.id,
    required this.orden,
    required this.maquina,
    this.direccion,
    this.latitud,
    this.longitud,
    required this.estado,
  });

  bool get completada => estado == 'completada';

  factory Parada.fromMap(Map<String, dynamic> m) => Parada(
        id: (m['id'] as num).toInt(),
        orden: (m['orden'] as num?)?.toInt() ?? 1,
        maquina: (m['maquina'] ?? 'Máquina') as String,
        direccion: m['direccion'] as String?,
        latitud: (m['latitud'] as num?)?.toDouble(),
        longitud: (m['longitud'] as num?)?.toDouble(),
        estado: (m['estado'] ?? 'pendiente') as String,
      );
}

class Ruta {
  final int id;
  final String nombre;
  final DateTime fecha;
  String estado;
  final String? motorizadoNombre;
  final List<Parada> paradas;

  Ruta({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.estado,
    this.motorizadoNombre,
    required this.paradas,
  });

  int get completadas => paradas.where((p) => p.completada).length;
  double get progreso => paradas.isEmpty ? 0 : completadas / paradas.length;

  factory Ruta.fromMap(Map<String, dynamic> m) {
    final rawParadas = (m['ruta_paradas'] as List?) ?? const [];
    final paradas = rawParadas
        .map((p) => Parada.fromMap(Map<String, dynamic>.from(p as Map)))
        .toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));

    final mot = m['motorizados'];
    return Ruta(
      id: (m['id'] as num).toInt(),
      nombre: (m['nombre'] ?? 'Ruta') as String,
      fecha: DateTime.parse(m['fecha'] as String),
      estado: (m['estado'] ?? 'pendiente') as String,
      motorizadoNombre: mot is Map ? mot['nombre'] as String? : null,
      paradas: paradas,
    );
  }
}

/// Resultado con diagnóstico: si viene vacío, [motivo] explica la causa.
class RutasResult {
  final List<Ruta> rutas;
  final String? motivo;
  const RutasResult(this.rutas, {this.motivo});
}

// ==========================================
// SERVICIO PRINCIPAL DE SUPABASE
// ==========================================

class VenduService {
  static final _db = Supabase.instance.client;

  /// Retorna el usuario únicamente si existe una sesión activa válida.
  static User? get user =>
      _db.auth.currentSession != null ? _db.auth.currentUser : null;

  // ---------------- AUTH ----------------

  static Future<AuthResponse> registrar({
    required String nombre,
    required String email,
    required String password,
  }) async {
    final res = await _db.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'nombre': nombre.trim(),
        'full_name': nombre.trim(), // Compatibilidad con ambas claves
      },
    );

    // Respaldo por si el trigger no está instalado y la sesión está activa
    if (res.session != null && res.user != null) {
      try {
        await _db.from('motorizados').upsert({
          'nombre': nombre.trim(),
          'email': email.trim(),
          'auth_user_id': res.user!.id,
        }, onConflict: 'auth_user_id');
      } catch (_) {}
    }
    return res;
  }

  static Future<AuthResponse> entrar({
    required String email,
    required String password,
  }) =>
      _db.auth.signInWithPassword(email: email.trim(), password: password);

  static Future<void> salir() => _db.auth.signOut();

  // ---------------- MOTORIZADO ----------------

  static Future<Motorizado?> miMotorizado() async {
    final u = user;
    if (u == null) return null;

    // 1) Búsqueda por auth_user_id
    final porAuth = await _db
        .from('motorizados')
        .select('id, nombre, email')
        .eq('auth_user_id', u.id)
        .maybeSingle();
    if (porAuth != null) return Motorizado.fromMap(porAuth);

    // 2) Respaldo por correo electrónico
    if (u.email != null) {
      final porEmail = await _db
          .from('motorizados')
          .select('id, nombre, email')
          .eq('email', u.email!)
          .maybeSingle();
      if (porEmail != null) {
        await _db
            .from('motorizados')
            .update({'auth_user_id': u.id}).eq('id', porEmail['id']);
        return Motorizado.fromMap(porEmail);
      }
    }

    // 3) Crear la ficha si no existe
    final nombreMeta = (u.userMetadata?['nombre'] as String?) ??
        (u.userMetadata?['full_name'] as String?);
    final nombre = nombreMeta ?? (u.email?.split('@').first ?? 'Motorizado');

    final creado = await _db
        .from('motorizados')
        .upsert({
          'nombre': nombre,
          'email': u.email,
          'auth_user_id': u.id,
        }, onConflict: 'auth_user_id')
        .select('id, nombre, email')
        .single();

    return Motorizado.fromMap(creado);
  }

  // ---------------- RUTAS ----------------

  static const _select = '''
    id, nombre, fecha, estado,
    motorizados ( nombre ),
    ruta_paradas ( id, orden, maquina, direccion, latitud, longitud, estado )
  ''';

  /// Carga las rutas del motorizado logueado.
  static Future<RutasResult> cargarRutas({bool todas = false}) async {
    final fechaHoy = DateTime.now().toIso8601String().split('T').first;

    if (todas) {
      final data = await _db
          .from('rutas')
          .select(_select)
          .eq('fecha', fechaHoy)
          .order('id');
      final rutas = _mapear(data);
      return RutasResult(
        rutas,
        motivo: rutas.isEmpty
            ? 'No hay ninguna ruta cargada con fecha de hoy. Corre el script 00_setup_vendu.sql o crea las rutas desde el dashboard.'
            : null,
      );
    }

    final mot = await miMotorizado();
    if (mot == null) {
      return const RutasResult(
        [],
        motivo: 'Tu usuario no está vinculado a un perfil de motorizado.',
      );
    }

    final data = await _db
        .from('rutas')
        .select(_select)
        .eq('motorizado_id', mot.id)
        .eq('fecha', fechaHoy)
        .order('id');

    var rutas = _mapear(data);
    if (rutas.isNotEmpty) return RutasResult(rutas);

    // Sin rutas hoy: buscamos las más recientes
    final recientes = await _db
        .from('rutas')
        .select(_select)
        .eq('motorizado_id', mot.id)
        .order('fecha', ascending: false)
        .limit(5);
    rutas = _mapear(recientes);

    return RutasResult(
      rutas,
      motivo: rutas.isEmpty
          ? '${mot.nombre} no tiene rutas asignadas. Asígnalas desde el dashboard o activa "Ver todo el equipo".'
          : 'No hay ruta para hoy. Mostrando las últimas asignadas a ${mot.nombre}.',
    );
  }

  // ---------------- REALTIME ----------------

  /// Emite paradas actualizadas en tiempo real para una ruta.
  static Stream<List<Parada>> escucharParadas(int rutaId) {
    return _db
        .from('ruta_paradas')
        .stream(primaryKey: ['id'])
        .eq('ruta_id', rutaId)
        .order('orden', ascending: true)
        .map((lista) => lista.map((m) => Parada.fromMap(m)).toList());
  }

  /// Suscribe un listener a cambios generales en la tabla de rutas.
  static RealtimeChannel suscribirARutas({
    required void Function() alActualizar,
  }) {
    final channel = _db.channel('public:rutas');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'rutas',
      callback: (payload) => alActualizar(),
    ).subscribe();
    return channel;
  }

  // ---------------- ACCIONES ----------------

  static List<Ruta> _mapear(dynamic data) => (data as List)
      .map((r) => Ruta.fromMap(Map<String, dynamic>.from(r as Map)))
      .toList();

  static Future<void> marcarParada(int paradaId, bool completada) =>
      _db.from('ruta_paradas').update({
        'estado': completada ? 'completada' : 'pendiente',
        'completada_at': completada ? DateTime.now().toIso8601String() : null,
      }).eq('id', paradaId);

  static Future<void> cambiarEstadoRuta(int rutaId, String estado) =>
      _db.from('rutas').update({'estado': estado}).eq('id', rutaId);
}