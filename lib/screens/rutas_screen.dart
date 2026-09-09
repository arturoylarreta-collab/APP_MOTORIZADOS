import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/vendu_service.dart';
import '../theme/theme.dart';

class RutasScreen extends StatefulWidget {
  const RutasScreen({super.key});

  @override
  State<RutasScreen> createState() => _RutasScreenState();
}

class _RutasScreenState extends State<RutasScreen> {
  List<Ruta> _rutas = [];
  String? _motivo;
  String? _error;
  bool _cargando = true;
  bool _verTodas = false;
  String _nombre = '';
  RealtimeChannel? _rutasChannel;

  @override
  void initState() {
    super.initState();
    _cargar();
    _suscribirRealtime();
  }

  @override
  void dispose() {
    _rutasChannel?.unsubscribe();
    super.dispose();
  }

  /// Escucha cambios en Supabase en tiempo real
  void _suscribirRealtime() {
    _rutasChannel = VenduService.suscribirARutas(
      alActualizar: () {
        if (mounted) _cargar(esSilencioso: true);
      },
    );
  }

  Future<void> _cargar({bool esSilencioso = false}) async {
    if (!esSilencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }

    try {
      final mot = await VenduService.miMotorizado();
      final res = await VenduService.cargarRutas(todas: _verTodas);
      if (!mounted) return;
      setState(() {
        _nombre = mot?.nombre ?? '';
        _rutas = res.rutas;
        _motivo = res.motivo;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted && !esSilencioso) setState(() => _cargando = false);
    }
  }

  Future<void> _marcar(Ruta ruta, Parada parada, bool valor) async {
    setState(() => parada.estado = valor ? 'completada' : 'pendiente');
    try {
      await VenduService.marcarParada(parada.id, valor);
      final nuevoEstado = ruta.completadas == ruta.paradas.length
          ? 'completada'
          : (ruta.completadas > 0 ? 'en_ruta' : 'pendiente');
      if (nuevoEstado != ruta.estado) {
        await VenduService.cambiarEstadoRuta(ruta.id, nuevoEstado);
        if (mounted) setState(() => ruta.estado = nuevoEstado);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => parada.estado = valor ? 'pendiente' : 'completada');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se guardó el cambio: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_nombre.isEmpty ? 'Rutas de hoy' : 'Hola, $_nombre'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : () => _cargar(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: VenduColors.amarillo,
        backgroundColor: VenduColors.negroSuave,
        onRefresh: () => _cargar(),
        child: _cargando
            ? const Center(
                child: CircularProgressIndicator(color: VenduColors.amarillo))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _EquipoToggle(
                    valor: _verTodas,
                    onChanged: (v) {
                      setState(() => _verTodas = v);
                      _cargar();
                    },
                  ),
                  if (_error != null) _Aviso(texto: _error!, esError: true),
                  if (_error == null && _motivo != null)
                    _Aviso(texto: _motivo!),
                  if (_rutas.isEmpty && _error == null && _motivo == null)
                    const _Aviso(texto: 'No hay rutas para mostrar.'),
                  ..._rutas.map((r) => _RutaCard(ruta: r, onMarcar: _marcar)),
                ],
              ),
      ),
    );
  }
}

class _EquipoToggle extends StatelessWidget {
  final bool valor;
  final ValueChanged<bool> onChanged;
  const _EquipoToggle({required this.valor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Text('Ver todo el equipo',
              style: TextStyle(color: VenduColors.gris, fontSize: 13)),
          const Spacer(),
          Switch(
            value: valor,
            activeThumbColor: VenduColors.amarillo,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  final bool esError;
  const _Aviso({required this.texto, this.esError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VenduColors.negroSuave,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: esError ? VenduColors.rojo : VenduColors.amarillo,
            width: 4,
          ),
        ),
      ),
      child: Text(texto,
          style: const TextStyle(color: VenduColors.gris, height: 1.4)),
    );
  }
}

class _RutaCard extends StatelessWidget {
  final Ruta ruta;
  final Future<void> Function(Ruta, Parada, bool) onMarcar;
  const _RutaCard({required this.ruta, required this.onMarcar});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: VenduColors.negroSuave,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ruta.nombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: VenduColors.blanco,
                        ),
                      ),
                    ),
                    _EstadoChip(estado: ruta.estado),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${ruta.completadas} de ${ruta.paradas.length} paradas'
                  '${ruta.motorizadoNombre != null ? ' · ${ruta.motorizadoNombre}' : ''}',
                  style: const TextStyle(color: VenduColors.gris, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ruta.progreso,
                    minHeight: 6,
                    backgroundColor: const Color(0xFF262B36),
                    valueColor: const AlwaysStoppedAnimation(
                        VenduColors.amarillo),
                  ),
                ),
              ],
            ),
          ),
          if (ruta.paradas.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text('Esta ruta no tiene paradas cargadas.',
                  style: TextStyle(color: VenduColors.gris)),
            )
          else
            ...ruta.paradas.asMap().entries.map((e) => _ParadaTile(
                  parada: e.value,
                  esUltima: e.key == ruta.paradas.length - 1,
                  onMarcar: (v) => onMarcar(ruta, e.value, v),
                )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ParadaTile extends StatelessWidget {
  final Parada parada;
  final bool esUltima;
  final ValueChanged<bool> onMarcar;
  const _ParadaTile({
    required this.parada,
    required this.esUltima,
    required this.onMarcar,
  });

  @override
  Widget build(BuildContext context) {
    final hecha = parada.completada;
    return InkWell(
      onTap: () => onMarcar(!hecha),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hecha ? VenduColors.amarillo : Colors.transparent,
                      border: Border.all(
                        color: hecha ? VenduColors.amarillo : VenduColors.gris,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: hecha
                        ? const Icon(Icons.check,
                            size: 16, color: VenduColors.negro)
                        : Text(
                            '${parada.orden}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: VenduColors.gris,
                                fontWeight: FontWeight.w700),
                          ),
                  ),
                  if (!esUltima)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: hecha
                            ? VenduColors.amarillo
                            : const Color(0xFF262B36),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 2, bottom: esUltima ? 8 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parada.maquina,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: hecha
                              ? VenduColors.gris
                              : VenduColors.blanco,
                          decoration:
                              hecha ? TextDecoration.lineThrough : null,
                          decorationColor: VenduColors.gris,
                        ),
                      ),
                      if (parada.direccion != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            parada.direccion!,
                            style: const TextStyle(
                                color: VenduColors.gris, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final String estado;
  const _EstadoChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (texto, color) = switch (estado) {
      'completada' => ('Completada', VenduColors.verde),
      'en_ruta' => ('En ruta', VenduColors.amarillo),
      _ => ('Pendiente', VenduColors.gris),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}