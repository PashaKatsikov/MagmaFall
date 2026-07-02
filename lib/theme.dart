import 'package:flutter/material.dart';

/// Cute, arcade volcano palette shared across all UI screens.
class MagmaColors {
  static const Color deepRock = Color(0xFF1A0D08);
  static const Color rock = Color(0xFF2E1A12);
  static const Color ember = Color(0xFFFF6A00);
  static const Color lava = Color(0xFFFF3B1F);
  static const Color gold = Color(0xFFFFC529);
  static const Color cream = Color(0xFFFFF3D6);
  static const Color shadow = Color(0xCC120704);
}

/// A chunky, glowing arcade-style text style used for titles and buttons.
TextStyle arcadeText({
  double size = 20,
  Color color = MagmaColors.cream,
  FontWeight weight = FontWeight.w800,
  double letterSpacing = 1.2,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: 1.1,
    shadows: const [
      Shadow(color: MagmaColors.shadow, offset: Offset(0, 2), blurRadius: 4),
    ],
  );
}

/// A reusable rounded, glossy arcade button.
class MagmaButton extends StatelessWidget {
  const MagmaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = MagmaColors.ember,
    this.width,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color color;
  final double? width;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final base = enabled ? color : Colors.grey.shade700;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onPressed : null,
          child: Ink(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(base, Colors.white, 0.25)!,
                  base,
                  Color.lerp(base, Colors.black, 0.25)!,
                ],
              ),
              border: Border.all(color: MagmaColors.deepRock, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: MagmaColors.shadow,
                  offset: Offset(0, 4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: MagmaColors.cream, size: 22),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: arcadeText(size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
