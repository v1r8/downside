import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'file_icons.dart';
import 'stacks.dart';

/// Barra das pilhas provisorias (deck de cartas), no topo do painel.
/// Aparece com mola quando ha pilhas; cada chip mostra um leque de
/// icones + contador; tocar expande o conteudo com animacao.
class StacksBar extends StatefulWidget {
  const StacksBar({super.key});

  @override
  State<StacksBar> createState() => _StacksBarState();
}

class _StacksBarState extends State<StacksBar> {
  int? _expanded;

  @override
  void initState() {
    super.initState();
    StacksController.i.stacks.addListener(_onChange);
  }

  @override
  void dispose() {
    StacksController.i.stacks.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    // Fecha o expandido se a pilha sumiu.
    if (_expanded != null &&
        !StacksController.i.stacks.value.any((s) => s.id == _expanded)) {
      _expanded = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stacks = StacksController.i.stacks.value;
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: stacks.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final s in stacks) _chip(s, scheme),
                    ],
                  ),
                  if (_expanded != null)
                    _detail(
                      stacks.firstWhere((s) => s.id == _expanded),
                      scheme,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _chip(FileStack s, ColorScheme scheme) {
    final active = _expanded == s.id;
    return TweenAnimationBuilder<double>(
      key: ValueKey(s.id),
      tween: Tween(begin: 0.8, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, t, child) =>
          Transform.scale(scale: t, child: child),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = active ? null : s.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _deck(s, 22, scheme),
              const SizedBox(width: 8),
              Text('${s.paths.length}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 2),
              Icon(active ? Icons.expand_less : Icons.expand_more,
                  size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Leque de icones (deck), do fundo para a frente.
  Widget _deck(FileStack s, double size, ColorScheme scheme) {
    final paths = s.paths.take(3).toList();
    final n = paths.length;
    return SizedBox(
      width: size + (n - 1) * size * 0.32,
      height: size,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: i * size * 0.32,
              child: Transform.rotate(
                angle: (i - (n - 1) / 2) * 0.14,
                child: Icon(iconForName(p.basename(paths[i])),
                    size: size, color: colorForName(p.basename(paths[i]), scheme)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(FileStack s, ColorScheme scheme) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final path in s.paths)
              _fileRow(s, path, scheme),
            const SizedBox(height: 6),
            Row(
              children: [
                _action(Icons.open_in_new, 'Abrir todos', () {
                  for (final path in s.paths) {
                    launchUrl(Uri.file(path));
                  }
                }, scheme),
                const SizedBox(width: 8),
                _action(Icons.close, 'Limpar', () {
                  StacksController.i.clearStack(s.id);
                }, scheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(FileStack s, String path, ColorScheme scheme) {
    final name = p.basename(path);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(iconForName(name), size: 18, color: colorForName(name, scheme)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5)),
          ),
          GestureDetector(
            onTap: () => StacksController.i.removeFromStack(s.id, path),
            child: Icon(Icons.close,
                size: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _action(
      IconData icon, String label, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
