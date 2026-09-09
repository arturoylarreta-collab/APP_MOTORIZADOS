import 'package:flutter/material.dart';
import '../services/vendu_service.dart';
import '../theme/theme.dart';
import '../widgets/vendu_logo.dart';
import 'rutas_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [RutasScreen(), _PerfilScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: VenduColors.negroSuave,
        indicatorColor: VenduColors.amarillo.withValues(alpha: 0.15),
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.route_outlined),
              selectedIcon: Icon(Icons.route, color: VenduColors.amarillo),
              label: 'Rutas'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: VenduColors.amarillo),
              label: 'Perfil'),
        ],
      ),
    );
  }
}

class _PerfilScreen extends StatelessWidget {
  const _PerfilScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: FutureBuilder<Motorizado?>(
        future: VenduService.miMotorizado(),
        builder: (context, snap) {
          final m = snap.data;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Center(child: VenduLogo(height: 72)),
              const SizedBox(height: 32),
              _Fila(etiqueta: 'Usuario', valor: m?.nombre ?? '—'),
              _Fila(
                  etiqueta: 'Correo',
                  valor: m?.email ?? VenduService.user?.email ?? '—'),
              _Fila(etiqueta: 'ID motorizado', valor: '${m?.id ?? '—'}'),
              const SizedBox(height: 32),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VenduColors.negroSuave,
                  foregroundColor: VenduColors.rojo,
                ),
                onPressed: VenduService.salir,
                child: const Text('Cerrar sesión'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Fila({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: const TextStyle(color: VenduColors.gris, fontSize: 12)),
          const SizedBox(height: 4),
          Text(valor,
              style: const TextStyle(
                  color: VenduColors.blanco,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
