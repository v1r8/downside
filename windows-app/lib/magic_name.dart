import 'package:flutter/material.dart';

/// Efeito "mágico" no lugar do nome enquanto a IA o gera: sparkle
/// pulsante + barra com varredura irisada. Portado do MagicName do Mac.
class MagicName extends StatefulWidget {
  const MagicName({super.key, this.width = 90, this.center = false});
  final double width;
  final bool center;

  @override
  State<MagicName> createState() => _MagicNameState();
}

class _MagicNameState extends State<MagicName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              widget.center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Opacity(
              opacity: 0.5 + 0.5 * (0.5 + 0.5 * (t * 2 - 1).abs()),
              child: Icon(Icons.auto_awesome, size: 11, color: scheme.primary),
            ),
            const SizedBox(width: 5),
            Container(
              width: widget.width,
              height: 9,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(
                  begin: Alignment(-1 + 2 * t, 0),
                  end: Alignment(1 + 2 * t, 0),
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    scheme.primary.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Etiqueta de tipo (PDF, PNG, LINK…) — pílula à direita do nome.
class TypeTag extends StatelessWidget {
  const TypeTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
