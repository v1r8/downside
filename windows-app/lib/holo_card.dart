import 'package:flutter/material.dart';

/// Cartinha holográfica (indicador de ação em massa) — varredura
/// irisada contínua, como no Mac.
class HoloCard extends StatefulWidget {
  const HoloCard({super.key, this.width = 13, this.height = 18});
  final double width;
  final double height;

  @override
  State<HoloCard> createState() => _HoloCardState();
}

class _HoloCardState extends State<HoloCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, -1),
              end: Alignment(1 + 2 * t, 1),
              colors: const [
                Color(0xFF7CE7FF),
                Color(0xFFB388FF),
                Colors.white,
                Color(0xFF7CE7FF),
              ],
              stops: const [0.0, 0.4, 0.55, 1.0],
            ),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.85), width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFFB388FF).withValues(alpha: 0.5),
                  blurRadius: 4),
            ],
          ),
        );
      },
    );
  }
}
