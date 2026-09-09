import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Muestra assets/logo.png.
/// Si el archivo todavía no existe, dibuja el logotipo con tipografía
/// para que la pantalla nunca se vea rota en la demo.
class VenduLogo extends StatelessWidget {
  final double height;
  const VenduLogo({super.key, this.height = 96});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      height: height,
      errorBuilder: (_, __, ___) => _Wordmark(height: height),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final double height;
  const _Wordmark({required this.height});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: height * 0.9,
          height: height * 0.9,
          decoration: BoxDecoration(
            color: VenduColors.amarillo,
            borderRadius: BorderRadius.circular(height * 0.26),
          ),
          alignment: Alignment.center,
          child: Text(
            'V',
            style: TextStyle(
              fontSize: height * 0.55,
              fontWeight: FontWeight.w900,
              color: VenduColors.negro,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'VENDU',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            color: VenduColors.blanco,
          ),
        ),
      ],
    );
  }
}
