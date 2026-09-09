// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isRegistering = false;

  // ---- Paleta Vendu ----
  static const _fondo = Color(0xFF0E1117);
  static const _superficie = Color(0xFF161922);
  static const _amarillo = Color(0xFFF5B800);
  static const _borde = Color(0xFF262B36);
  static const _gris = Color(0xFF9CA3AF);

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Lo que importa es la SESIÓN, no el user.
      // Sin sesión, Supabase responde a la app como anónimo y RLS
      // devuelve cero rutas sin dar error.
      if (supabase.auth.currentSession == null) {
        _aviso('Tu correo aún no está confirmado. Revisa tu bandeja.');
        return;
      }
      await _vincularMotorizado();
      if (mounted) _irAlHome();
    } on AuthException catch (e) {
      _aviso(e.message == 'Invalid login credentials'
          ? 'Correo o contraseña incorrectos.'
          : e.message);
    } catch (e) {
      _aviso('Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final nombre = _nameController.text.trim();

      await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        // Mandamos la misma clave con los dos nombres para que el
        // trigger de Supabase encuentre el nombre en cualquier caso.
        data: {'nombre': nombre, 'full_name': nombre},
      );

      // Sin sesión no se puede entrar: hay confirmación de correo activa.
      if (supabase.auth.currentSession == null) {
        _aviso('Cuenta creada. Confirma tu correo y vuelve a entrar.');
        if (mounted) setState(() => _isRegistering = false);
        return;
      }

      await _vincularMotorizado();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bienvenido a Vendu, $nombre'),
          backgroundColor: Colors.green.shade800,
        ),
      );
      _irAlHome();
    } on AuthException catch (e) {
      _aviso(e.message.contains('already registered')
          ? 'Ese correo ya tiene cuenta. Inicia sesión.'
          : e.message);
    } catch (e) {
      _aviso('Error inesperado al registrar: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Garantiza que exista la fila en `motorizados` ligada a este usuario.
  /// Sin este vínculo, `rutas.motorizado_id` nunca coincide y la lista
  /// de rutas sale vacía.
  Future<void> _vincularMotorizado() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata ?? {};
    final nombre = (meta['nombre'] ?? meta['full_name']) as String? ??
        (user.email?.split('@').first ?? 'Motorizado');

    try {
      await supabase.from('motorizados').upsert({
        'nombre': nombre,
        'email': user.email,
        'auth_user_id': user.id,
      }, onConflict: 'auth_user_id');
    } catch (_) {
      // El trigger on_auth_user_created ya lo creó. Seguimos.
    }
  }

  void _irAlHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: Colors.red.shade900),
    );
  }

  InputDecoration _campo({
    required String label,
    required IconData icono,
    String? ayuda,
    Widget? suffix,
  }) {
    OutlineInputBorder borde(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _gris),
      helperText: ayuda,
      helperStyle: const TextStyle(color: _gris, fontSize: 12),
      filled: true,
      fillColor: _superficie,
      prefixIcon: Icon(icono, color: _amarillo),
      suffixIcon: suffix,
      enabledBorder: borde(_borde),
      focusedBorder: borde(_amarillo, 1.5),
      errorBorder: borde(Colors.redAccent),
      focusedErrorBorder: borde(Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- LOGO VENDU ----
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 22),
                        decoration: BoxDecoration(
                          color: _superficie,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _amarillo, width: 1.5),
                        ),
                        child: Image.asset(
                          'assets/logo.png',
                          height: 76,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.two_wheeler,
                                  size: 64, color: _amarillo),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'VENDU LOGÍSTICA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegistering
                          ? 'Crea tu cuenta para iniciar operaciones'
                          : 'Ingresa tus credenciales para iniciar ruta',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _gris, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: Colors.white),
                        decoration: _campo(
                          label: 'Usuario (tu nombre)',
                          icono: Icons.person_outline,
                          ayuda: 'Así te ve la oficina en el dashboard',
                        ),
                        validator: (value) {
                          if (!_isRegistering) return null;
                          if (value == null || value.trim().length < 2) {
                            return 'Ingresa tu nombre o usuario';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                    ],

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: _campo(
                        label: 'Correo electrónico',
                        icono: Icons.email_outlined,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa tu correo';
                        }
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())) {
                          return 'Ingresa un correo válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      onFieldSubmitted: (_) => _isLoading
                          ? null
                          : (_isRegistering
                              ? _handleRegister()
                              : _handleLogin()),
                      decoration: _campo(
                        label: 'Contraseña',
                        icono: Icons.lock_outline,
                        ayuda: _isRegistering ? 'Mínimo 6 caracteres' : null,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: _gris,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa tu contraseña';
                        }
                        if (value.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 30),

                    ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (_isRegistering ? _handleRegister : _handleLogin),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: _amarillo,
                        foregroundColor: _fondo,
                        disabledBackgroundColor: _amarillo.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _fondo,
                              ),
                            )
                          : Text(
                              _isRegistering ? 'Crear cuenta' : 'Iniciar sesión',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() {
                                _isRegistering = !_isRegistering;
                                _formKey.currentState?.reset();
                              }),
                      child: Text(
                        _isRegistering
                            ? '¿Ya tienes una cuenta? Inicia sesión'
                            : '¿No tienes cuenta? Regístrate aquí',
                        style: const TextStyle(
                          color: _amarillo,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
