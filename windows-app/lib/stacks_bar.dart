import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';

import 'drop_util.dart';
import 'fichario.dart';
import 'file_icons.dart';
import 'stacks.dart';
import 'win_shell.dart';

/// Barra das pilhas provisorias (deck de cartas). Aparece quando ha
/// pilhas OU durante um arrasto (mostrando zonas de drop): cada pilha
/// e um alvo (empilha) e ha a zona "Nova pilha".
class StacksBar extends StatefulWidget {
  const StacksBar({super.key});

  @override
  State<StacksBar> createState() => _StacksBarState();
}

class _StacksBarState extends State<StacksBar> {
  int? _expanded;
  int? _target; // chip sob o cursor durante o drop
  bool _newTarget = false;
  bool _trashTarget = false;

  @override
  void initState() {
    super.initState();
    StacksController.i.stacks.addListener(_onChange);
    DragWatch.active.addListener(_onChange);
  }

  @override
  void dispose() {
    StacksController.i.stacks.removeListener(_onChange);
    DragWatch.active.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
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
    final dragging = DragWatch.active.value;
    final show = dragging || stacks.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Esquerda: zona de exclusão (Lixeira).
                      if (dragging) _springIn(_trashZone(scheme)),
                      for (final s in stacks) _chip(s, scheme, dragging),
                      // Direita: adicionar nova pilha.
                      if (dragging &&
                          stacks.length < StacksController.maxStacks)
                        _springIn(_newStackZone(scheme)),
                    ],
                  ),
                  if (_expanded != null && !dragging)
                    _detail(
                      stacks.firstWhere((s) => s.id == _expanded),
                      scheme,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _chip(FileStack s, ColorScheme scheme, bool dragging) {
    final active = _expanded == s.id;
    final targeted = _target == s.id;
    final visual = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: targeted
            ? scheme.primary.withValues(alpha: 0.35)
            : active
                ? scheme.primary.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: targeted || active
              ? scheme.primary.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.10),
          width: targeted ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _deck(s.paths, 22, scheme),
          const SizedBox(width: 8),
          Text('${s.paths.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          if (!dragging) ...[
            const SizedBox(width: 2),
            Icon(active ? Icons.expand_less : Icons.expand_more,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    // Alvo de drop (empilhar arquivos) + arrastavel para o fichario.
    final dropTarget = DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (_) {
        DragWatch.ping();
        if (_target != s.id) setState(() => _target = s.id);
        return DropOperation.copy;
      },
      onDropLeave: (_) {
        if (_target == s.id) setState(() => _target = null);
      },
      onPerformDrop: (event) async {
        final paths = await readDroppedPaths(event);
        if (paths.isNotEmpty) StacksController.i.addTo(s.id, paths);
        setState(() => _target = null);
      },
      child: GestureDetector(
        onTap: () => setState(() => _expanded = active ? null : s.id),
        child: visual,
      ),
    );

    return Draggable<int>(
      data: s.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: _deck(s.paths, 26, scheme)),
      ),
      child: dropTarget,
    );
  }

  /// Entrada com mola (overshoot) para deixar claro que é alvo de drop.
  Widget _springIn(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.elasticOut,
      builder: (context, t, c) => Transform.scale(
        scale: t.clamp(0.0, 1.2),
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: c),
      ),
      child: child,
    );
  }

  Widget _trashZone(ColorScheme scheme) {
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (_) {
        DragWatch.ping();
        if (!_trashTarget) setState(() => _trashTarget = true);
        return DropOperation.copy;
      },
      onDropLeave: (_) {
        if (_trashTarget) setState(() => _trashTarget = false);
      },
      onPerformDrop: (event) async {
        final paths = await readDroppedPaths(event);
        if (paths.isNotEmpty) WinShell.moveToRecycleBin(paths);
        setState(() => _trashTarget = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _trashTarget
              ? const Color(0xFFE5534B).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE5534B)
                .withValues(alpha: _trashTarget ? 0.9 : 0.4),
          ),
        ),
        child: Icon(Icons.delete_outline,
            size: 18,
            color: _trashTarget ? Colors.white : const Color(0xFFE5534B)),
      ),
    );
  }

  Widget _newStackZone(ColorScheme scheme) {
    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (_) {
        DragWatch.ping();
        if (!_newTarget) setState(() => _newTarget = true);
        return DropOperation.copy;
      },
      onDropLeave: (_) {
        if (_newTarget) setState(() => _newTarget = false);
      },
      onPerformDrop: (event) async {
        final paths = await readDroppedPaths(event);
        if (paths.isNotEmpty) StacksController.i.createWith(paths);
        setState(() => _newTarget = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _newTarget
              ? scheme.primary.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.primary.withValues(alpha: _newTarget ? 0.8 : 0.4),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            const Text('Nova pilha', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _detail(FileStack s, ColorScheme scheme) {
    return Container(
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
          for (final path in s.paths) _fileRow(s, path, scheme),
          const SizedBox(height: 6),
          Row(
            children: [
              _action(Icons.open_in_new, 'Abrir todos', () {
                for (final path in s.paths) {
                  launchUrl(Uri.file(path));
                }
              }, scheme),
              const SizedBox(width: 8),
              _action(Icons.archive_outlined, 'Arquivar', () {
                FicharioStore.i.archive(s);
                StacksController.i.clearStack(s.id);
              }, scheme),
              const SizedBox(width: 8),
              _action(Icons.close, 'Limpar', () {
                StacksController.i.clearStack(s.id);
              }, scheme),
            ],
          ),
        ],
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
            child: Icon(Icons.close, size: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _deck(List<String> paths, double size, ColorScheme scheme) {
    final shown = paths.take(3).toList();
    final n = shown.length;
    return SizedBox(
      width: size + (n <= 1 ? 0 : (n - 1) * size * 0.32),
      height: size,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          for (var idx = 0; idx < n; idx++)
            Positioned(
              left: idx * size * 0.32,
              child: Transform.rotate(
                angle: (idx - (n - 1) / 2) * 0.14,
                child: Icon(iconForName(p.basename(shown[idx])),
                    size: size,
                    color: colorForName(p.basename(shown[idx]), scheme)),
              ),
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
