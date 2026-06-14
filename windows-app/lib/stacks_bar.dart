import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bulk_actions.dart';
import 'dashed_border.dart';
import 'drop_util.dart';
import 'fichario.dart';
import 'file_icons.dart';
import 'holo_card.dart';
import 'magic_name.dart';
import 'stacks.dart';
import 'win_shell.dart';

/// Barra das pilhas provisorias (deck de cartas). Aparece quando ha
/// pilhas OU durante um arrasto (mostrando zonas de drop): cada pilha
/// e um alvo (empilha), a lixeira (esquerda) e a zona "Nova pilha"
/// (direita) crescem com mola para preencher a barra inteira.
class StacksBar extends StatefulWidget {
  const StacksBar({super.key});

  @override
  State<StacksBar> createState() => _StacksBarState();
}

class _StacksBarState extends State<StacksBar>
    with SingleTickerProviderStateMixin {
  int? _expanded;
  int? _target; // chip sob o cursor durante o drop de arquivos
  bool _newTarget = false;
  bool _trashTarget = false;
  int? _runningId;
  String? _runningLabel;
  String? _runningMsg;
  int? _runningMsgId;

  // Arrasto de um CHIP de pilha (Draggable<int>) — diferente do arrasto
  // de arquivos do sistema (DragWatch). Faz a lixeira aparecer.
  bool _stackDragging = false;

  // Tipo do ultimo arrasto ativo — preservado durante a saida para que
  // as zonas encolham (mola) em vez de sumirem (teletransporte).
  bool _lastFileDrag = false;

  // Largura natural do bloco de chips — medida apos o layout, para
  // dimensionar as zonas que preenchem o restante da barra.
  final GlobalKey _chipsKey = GlobalKey();
  double _chipsW = 0;

  late final AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    StacksController.i.stacks.addListener(_onChange);
    StacksController.i.naming.addListener(_repaint);
    StacksController.i.renaming.addListener(_repaint);
    DragWatch.active.addListener(_onChange);
  }

  @override
  void dispose() {
    StacksController.i.stacks.removeListener(_onChange);
    StacksController.i.naming.removeListener(_repaint);
    StacksController.i.renaming.removeListener(_repaint);
    DragWatch.active.removeListener(_onChange);
    _reveal.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    if (_expanded != null &&
        !StacksController.i.stacks.value.any((s) => s.id == _expanded)) {
      _expanded = null;
    }
    _syncReveal();
    if (mounted) setState(() {});
  }

  bool get _anyDrag => DragWatch.active.value || _stackDragging;

  /// Liga/desliga a animacao-mola das zonas conforme ha arrasto.
  void _syncReveal() {
    final anyDrag = _anyDrag;
    if (anyDrag) {
      _lastFileDrag = DragWatch.active.value;
      if (_reveal.status != AnimationStatus.completed &&
          _reveal.status != AnimationStatus.forward) {
        _reveal.forward();
      }
    } else {
      if (_reveal.status != AnimationStatus.dismissed &&
          _reveal.status != AnimationStatus.reverse) {
        _reveal.reverse();
      }
    }
  }

  void _measureChips() {
    final ctx = _chipsKey.currentContext;
    final w = ctx?.size?.width;
    if (w != null && (w - _chipsW).abs() > 0.5) {
      _chipsW = w;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stacks = StacksController.i.stacks.value;
    final show = _anyDrag || stacks.isNotEmpty;
    SchedulerBinding.instance.addPostFrameCallback((_) => _measureChips());
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
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _reveal,
                      builder: (context, _) => _bar(stacks, scheme),
                    ),
                  ),
                  if (_expanded != null && !_anyDrag)
                    _detail(
                      stacks.firstWhere((s) => s.id == _expanded),
                      scheme,
                    ),
                ],
              ),
            ),
    );
  }

  /// A barra: lixeira (esquerda) | chips | nova pilha (direita). As zonas
  /// crescem do zero ate dividir o espaco livre — preenche a barra toda.
  Widget _bar(List<FileStack> stacks, ColorScheme scheme) {
    final t = Curves.easeOutCubic.transform(_reveal.value);
    final spring = Curves.elasticOut.transform(_reveal.value);
    final visible = _reveal.value > 0.001;
    final canAddNew = stacks.length < StacksController.maxStacks;

    final showTrash = visible;
    final showNew = visible && _lastFileDrag && canAddNew;
    final zoneCount = (showTrash ? 1 : 0) + (showNew ? 1 : 0);

    return LayoutBuilder(
      builder: (context, c) {
        final total = c.maxWidth.isFinite ? c.maxWidth : 0.0;
        final free = (total - _chipsW).clamp(0.0, total);
        final perZone = zoneCount > 0 ? (free / zoneCount) * t : 0.0;
        return Row(
          children: [
            if (showTrash)
              _zoneSlot(
                width: perZone,
                t: t,
                spring: spring,
                child: _trashZone(scheme),
              ),
            Flexible(
              fit: FlexFit.loose,
              child: Row(
                key: _chipsKey,
                mainAxisSize: MainAxisSize.min,
                children: [for (final s in stacks) _chip(s, scheme)],
              ),
            ),
            if (showNew)
              _zoneSlot(
                width: perZone,
                t: t,
                spring: spring,
                child: _newStackZone(scheme),
              ),
          ],
        );
      },
    );
  }

  /// Caixa de uma zona de drop: largura animada (mola), conteudo
  /// centralizado, recortado durante o crescimento (sem teletransporte).
  Widget _zoneSlot({
    required double width,
    required double t,
    required double spring,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: ClipRect(
        child: Opacity(
          opacity: t.clamp(0.0, 1.0),
          // Mola sutil — sem teletransporte (a largura ja cresce suave).
          child: Transform.scale(scale: 0.85 + 0.15 * spring, child: child),
        ),
      ),
    );
  }

  Widget _chip(FileStack s, ColorScheme scheme) {
    final dragging = _anyDrag;
    final active = _expanded == s.id;
    final targeted = _target == s.id;
    final naming = StacksController.i.naming.value.contains(s.id);
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
          _deck(s.paths, 22, scheme, holo: s.hadBulkAction),
          const SizedBox(width: 8),
          Text('${s.paths.length}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          if (!dragging) ...[
            const SizedBox(width: 6),
            if (naming)
              const MagicName(width: 54)
            else if (s.name != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(s.name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(width: 2),
            Icon(active ? Icons.expand_less : Icons.expand_more,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    // Alvo de drop (empilhar arquivos) + arrastavel para o fichario/lixeira.
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
      onDragStarted: () {
        setState(() => _stackDragging = true);
        _syncReveal();
      },
      onDragEnd: (_) => _endStackDrag(),
      onDraggableCanceled: (_, __) => _endStackDrag(),
      onDragCompleted: _endStackDrag,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: _deck(s.paths, 26, scheme)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: visual),
      child: dropTarget,
    );
  }

  void _endStackDrag() {
    setState(() => _stackDragging = false);
    _syncReveal();
  }

  void _deleteStack(int id) {
    final list = StacksController.i.stacks.value.where((s) => s.id == id);
    if (list.isNotEmpty) WinShell.moveToRecycleBin(list.first.paths);
    StacksController.i.clearStack(id);
  }

  Widget _trashZone(ColorScheme scheme) {
    const red = Color(0xFFE5534B);
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _deleteStack(d.data),
      builder: (context, cand, rej) {
        final hot = _trashTarget || cand.isNotEmpty;
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
          child: DashedBox(
            color: red.withValues(alpha: hot ? 1 : 0.55),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: hot ? red.withValues(alpha: 0.30) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline,
                      size: 18, color: hot ? Colors.white : red),
                  const SizedBox(width: 6),
                  Text('Lixeira',
                      style: TextStyle(
                          fontSize: 12, color: hot ? Colors.white : red)),
                ],
              ),
            ),
          ),
        );
      },
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
      child: DashedBox(
        color: scheme.primary.withValues(alpha: _newTarget ? 1 : 0.55),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _newTarget
                ? scheme.primary.withValues(alpha: 0.30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
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
      ),
    );
  }

  Widget _detail(FileStack s, ColorScheme scheme) {
    final originals = s.paths.where((path) => !s.outputs.contains(path)).toList();
    final outputs = s.paths.where((path) => s.outputs.contains(path)).toList();
    final running = _runningId == s.id;
    final naming = StacksController.i.naming.value.contains(s.id);
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
          // Cabecalho: nome da pilha (IA) + botao para (re)nomear.
          Row(
            children: [
              Icon(Icons.tag, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: naming
                    ? const MagicName(width: 120)
                    : Text(
                        s.name ?? 'Pilha sem nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: s.name == null
                              ? scheme.onSurfaceVariant
                              : null,
                        ),
                      ),
              ),
              GestureDetector(
                onTap: naming
                    ? null
                    : () => StacksController.i.renameStackWithAI(s.id),
                child: Tooltip(
                  message: 'Nomear pilha com IA local',
                  child: Icon(Icons.auto_awesome,
                      size: 15, color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final path in originals) _fileRow(s, path, scheme),
          if (outputs.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [for (final o in outputs) _outputChip(s, o, scheme)],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (running)
            Row(
              children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_runningLabel ?? '…',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _action(Icons.open_in_new, 'Abrir', () {
                  for (final path in s.paths) {
                    launchUrl(Uri.file(path));
                  }
                }, scheme),
                _action(Icons.drive_file_rename_outline, 'Renomear arquivos',
                    () => _runRename(s), scheme),
                _action(Icons.link, 'Baixar links',
                    () => _run(s, 'Baixando…', BulkRunner.downloadLinks), scheme),
                _action(Icons.summarize_outlined, 'Resumir',
                    () => _run(s, 'Resumindo…', BulkRunner.summarize), scheme),
                _action(Icons.sell_outlined, 'Palavras-chave',
                    () => _run(s, 'Caracterizando…', BulkRunner.keywords), scheme),
                _action(Icons.archive_outlined, 'Arquivar', () {
                  FicharioStore.i.archive(s);
                  StacksController.i.clearStack(s.id);
                }, scheme),
                _action(Icons.close, 'Limpar',
                    () => StacksController.i.clearStack(s.id), scheme),
              ],
            ),
          if (_runningMsg != null && running == false && _runningMsgId == s.id)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_runningMsg!,
                  style:
                      TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  /// Output (gerado por IA/ação): chip com ✨ + brilho holográfico.
  Widget _outputChip(FileStack s, String path, ColorScheme scheme) {
    final name = p.basename(path);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFB388FF).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFB388FF).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HoloCard(width: 10, height: 14),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => launchUrl(Uri.file(path)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5)),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => StacksController.i.removeFromStack(s.id, path),
            child: Icon(Icons.close, size: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _run(FileStack s, String label,
      Future<List<String>> Function(FileStack) action) async {
    if (_runningId != null) return;
    setState(() {
      _runningId = s.id;
      _runningLabel = label;
      _runningMsg = null;
    });
    String msg;
    try {
      final outs = await action(s);
      for (final o in outs) {
        StacksController.i.addOutput(s.id, o);
      }
      msg = outs.isEmpty ? 'Nada para processar' : 'Concluído ✓';
    } on NoAIException {
      msg = 'Precisa de IA: Ollama rodando ou chave do Claude';
    } catch (_) {
      msg = 'Não foi possível concluir';
    }
    _finishRun(s, msg);
  }

  /// Renomeia os arquivos da pilha no disco (IA local) com spinner e
  /// mensagem — sem gerar "outputs".
  Future<void> _runRename(FileStack s) async {
    if (_runningId != null) return;
    setState(() {
      _runningId = s.id;
      _runningLabel = 'Renomeando…';
      _runningMsg = null;
    });
    String msg;
    try {
      final n = await StacksController.i.renameAllWithAI(s.id);
      msg = n == 0
          ? 'Nada renomeado (IA local indisponível?)'
          : 'Renomeados $n ✓';
    } catch (_) {
      msg = 'Não foi possível renomear';
    }
    _finishRun(s, msg);
  }

  void _finishRun(FileStack s, String msg) {
    if (!mounted) return;
    setState(() {
      _runningId = null;
      _runningLabel = null;
      _runningMsg = msg;
      _runningMsgId = s.id;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _runningMsg == msg) setState(() => _runningMsg = null);
    });
  }

  Widget _fileRow(FileStack s, String path, ColorScheme scheme) {
    final name = p.basename(path);
    final renaming = StacksController.i.renaming.value.contains(path);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(iconForName(name), size: 18, color: colorForName(name, scheme)),
          const SizedBox(width: 8),
          Expanded(
            child: renaming
                ? const MagicName(width: 120)
                : Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5)),
          ),
          if (!renaming)
            GestureDetector(
              onTap: () => StacksController.i.renameFileOnDisk(s.id, path),
              child: Tooltip(
                message: 'Renomear este arquivo com IA local',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.auto_awesome,
                      size: 14, color: scheme.primary),
                ),
              ),
            ),
          GestureDetector(
            onTap: () => StacksController.i.removeFromStack(s.id, path),
            child: Icon(Icons.close, size: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _deck(List<String> paths, double size, ColorScheme scheme,
      {bool holo = false}) {
    final shown = paths.take(3).toList();
    final n = shown.length;
    final shift = holo ? size * 0.42 : 0.0;
    return SizedBox(
      width: shift + size + (n <= 1 ? 0 : (n - 1) * size * 0.32),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          if (holo)
            Positioned(
              left: 0,
              child: Transform.rotate(
                angle: -0.18,
                child: HoloCard(width: size * 0.62, height: size * 0.88),
              ),
            ),
          for (var idx = 0; idx < n; idx++)
            Positioned(
              left: shift + idx * size * 0.32,
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
