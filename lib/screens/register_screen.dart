import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/vendu_service.dart';
import '../theme/theme.dart';
import '../widgets/vendu_logo.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  String? _validar() {
    if (_nombre.text.trim().length < 2) return 'Escribe tu nombre.';
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Ese correo no es válido.';
    }
    if (_pass.text.length < 6) {
      return 'La contraseña necesita al menos 6 caracteres.';
    }
    return null;
  }

  Future<void> _registrar() async {
    final falla = _validar();
    if (falla != null) {
      setState(() => _error = falla);
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await VenduService.registrar(
        nombre: _nombre.text,
        email: _email.text,
        password: _pass.text,
      );
      if (!mounted) return;

      final haySesion = Supabase.instance.client.auth.currentSession != null;
      if (haySesion) {
        Navigator.pop(context); // el AuthGate lleva al Home
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cuenta creada. Confirma el correo y vuelve a entrar.'),
          ),
        );
      }
    } catch (e) {
      final s = e.toString();
      setState(() => _error = s.contains('already registered')
          ? 'Ese correo ya tiene una cuenta. Entra con tu contraseña.'
          : 'No se pudo crear la cuenta: $s');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: VenduLogo(height: 72)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Usuario (tu nombre)',
                      helperText: 'Así te ve la oficina en el dashboard',
                      helperStyle: TextStyle(color: VenduColors.gris),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Correo'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      helperText: 'Mínimo 6 caracteres',
                      helperStyle: TextStyle(color: VenduColors.gris),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        style: const TextStyle(color: VenduColors.rojo)),
                  ],
                  const SizedBox(height: 26),
                  FilledButton(
                    onPressed: _cargando ? null : _registrar,
                    child: _cargando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: VenduColors.negro),
                          )
                        : const Text('Crear cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
