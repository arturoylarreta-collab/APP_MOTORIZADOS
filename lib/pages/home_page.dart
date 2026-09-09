import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _supabase = Supabase.instance.client;
  bool _isTrackingActive = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _paradas = [];

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    _fetchParadas();
  }

  // Verifica si el servicio en segundo plano ya se está ejecutando
  Future<void> _checkServiceStatus() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    setState(() {
      _isTrackingActive = isRunning;
    });
  }

  // Carga las paradas asignadas al motorizado desde Supabase
  Future<void> _fetchParadas() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('rutas_paradas')
          .select('*')
          .eq('motorizado_id', userId)
          .order('orden', ascending: true);

      setState(() {
        _paradas = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar paradas: $e')),
        );
      }
    }
  }

  // Alterna el servicio de GPS en segundo plano
  Future<void> _toggleTracking() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (isRunning) {
      service.invoke("stopService");
      setState(() => _isTrackingActive = false);
    } else {
      final started = await service.startService();
      setState(() => _isTrackingActive = started);
    }
  }

  // Cerrar sesión
  Future<void> _logout() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke("stopService");
    }
    await _supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
  

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta Vendu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Cerrar Sesión',
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchParadas,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tarjeta de Estado del Rastreo GPS
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: _isTrackingActive ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        _isTrackingActive ? Icons.location_on : Icons.location_off,
                        size: 36,
                        color: _isTrackingActive ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isTrackingActive ? 'Rastreo Activo' : 'Rastreo Inactivo',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isTrackingActive ? Colors.green.shade900 : Colors.red.shade900,
                              ),
                            ),
                            Text(
                              _isTrackingActive
                                  ? 'Transmitiendo ubicación...'
                                  : 'Inicia ruta para transmitir GPS',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _toggleTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTrackingActive ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_isTrackingActive ? 'Detener' : 'Iniciar'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text(
                'Paradas Asignadas',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),

              // Lista de Paradas
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_paradas.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0),
                    child: Text('No tienes paradas asignadas para hoy.'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _paradas.length,
                  itemBuilder: (context, index) {
                    final parada = _paradas[index];
                    final estado = parada['estado'] ?? 'pendiente';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${index + 1}'),
                        ),
                        title: Text(parada['nombre_punto'] ?? 'Parada ${index + 1}'),
                        subtitle: Text(parada['direccion'] ?? 'Sin dirección'),
                        trailing: Chip(
                          label: Text(
                            estado.toUpperCase(),
                            style: const TextStyle(fontSize: 11, color: Colors.white),
                          ),
                          backgroundColor: estado == 'completada'
                              ? Colors.green
                              : (estado == 'en_proceso' ? Colors.orange : Colors.grey),
                        ),
                        onTap: () {
                          // Acción al tocar la parada (ej. detalle / foto / firma)
                        },
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