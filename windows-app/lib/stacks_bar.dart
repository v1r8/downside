import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bulk_actions.dart';
import 'dashed_border.dart';
import 'drop_util.dart';
import 'fichario.dart';
import 'file_card.dart';
import 'file_icons.dart';
import 'holo_card.dart';
import 'magic_name.dart';
import 'prefs.dart';
import 'preview.dart';
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

  // Controla a transição contínua (entrada e volta) das zonas de drop.
  late final AnimationController _t;

  // Pesos de flex: a lixeira é mais estreita que a "Nova pilha".
  static const double _chipWeight = 100;
  static const double _trashWeight = 64;
  static const double _newWeight = 124;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 340),
    );
    StacksController.i.stacks.addListener(_onChange);
    StacksController.i.naming.addListener(_repaint);
    StacksController.i.renaming.addListener(_repaint);
    Prefs.i.cardLightBackground.addListener(_repaint);
    DragWatch.active.addListener(_onChange);
  }

  @override
  void dispose() {
    StacksController.i.stacks.removeListener(_onChange);
    StacksController.i.naming.removeListener(_repaint);
    StacksController.i.renaming.removeListener(_repaint);
    Prefs.i.cardLightBackground.removeListener(_repaint);
    DragWatch.active.removeListener(_onChange);
    _t.dispose();
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
    _sync();
    if (mounted) setState(() {});
  }

  bool get _anyDrag => DragWatch.active.value;

  /// Avança/recua a animação conforme há (ou não) arrasto. Mesma curva
  /// nos dois sentidos — entrada e volta são contínuas, sem saltos.
  void _sync() {
    if (_anyDrag) {
      if (_t.status != AnimationStatus.completed &&
          _t.status != AnimationStatus.forward) {
        _t.forward();
      }
    } else if (_t.status != AnimationStatus.dismissed &&
        _t.status != AnimationStatus.reverse) {
      _t.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Tudo dentro do AnimatedBuilder: 'show', as zonas e os chips são
    // reavaliados a cada quadro, então a VOLTA também anima (sem snap).
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final stacks = StacksController.i.stacks.value;
        final show = _anyDrag || _t.value > 0.001 || stacks.isNotEmpty;
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: double.infinity, child: _bar(stacks, scheme)),
                      if (_expanded != null && !_anyDrag)
                        _detail(
                          stacks.firstWhere((s) => s.id == _expanded),
                          scheme,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  /// A barra preenche toda a largura. Em repouso, os chips se dividem o
  /// espaço. Durante o arrasto, a lixeira (esquerda) e a "Nova pilha"
  /// (direita) CRESCEM continuamente (flex animado) empurrando os chips —
  /// e ENCOLHEM do mesmo jeito ao soltar. Sem saltos.
  Widget _bar(List<FileStack> stacks, ColorScheme scheme) {
    final t = Curves.easeInOutCubic.transform(_t.value);
    final canAddNew = stacks.length < StacksController.maxStacks;
    final showZones = _t.value > 0.001;
    final showTrash = showZones;
    final showNew = showZones && canAddNew;

    int flex(double w) => (w * 1000).round().clamp(1, 1 << 20).toInt();

    return Row(
      children: [
        if (showTrash)
          Expanded(
            flex: flex(_trashWeight * t),
            child: _zoneFade(t, _trashZone(scheme)),
          ),
        for (final s in stacks)
          Expanded(flex: flex(_chipWeight), child: _chip(s, scheme)),
        if (showNew)
          Expanded(
            flex: flex(_newWeight * t),
            child: _zoneFade(t, _newStackZone(scheme)),
          ),
      ],
    );
  }

  /// Conteúdo da zona aparece/some junto com a largura (opacidade ligada
  /// ao progresso) — a transição fica contínua, sem piscar.
  Widget _zoneFade(double t, Widget child) {
    return Padding(
      // Folga lateral — evita as zonas colarem entre si e nos chips.
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ClipRect(
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
    );
  }

  Widget _chip(FileStack s, ColorScheme scheme) {
    final dragging = _anyDrag;
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
      // Conteúdo (ícone empilhado + contador, e o nome) CENTRALIZADO no
      // retângulo; o chevron fica ancorado no canto direito.
      child: Row(
        children: [
          if (!dragging) const SizedBox(width: 18),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _deck(s.paths, 22, scheme, holo: s.hadBulkAction),
                  const SizedBox(width: 8),
                  Text('${s.paths.length}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          if (!dragging)
            SizedBox(
              width: 18,
              child: Icon(active ? Icons.expand_less : Icons.expand_more,
                  size: 16, color: scheme.onSurfaceVariant),
            ),
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
        DragWatch.end();
      },
      child: GestureDetector(
        onTap: () => setState(() => _expanded = active ? null : s.id),
        child: visual,
      ),
    );

    // Arrasto REAL do sistema: leva os arquivos da pilha para outros apps
    // (Explorer, e-mail, etc.). Como sai como fileUri, as zonas internas
    // (lixeira/nova pilha/fichário) também reagem via DropRegion.
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final item = DragItem();
        for (final path in s.paths) {
          item.add(Formats.fileUri(Uri.file(path)));
        }
        return item;
      },
      child: DraggableWidget(child: dropTarget),
    );
  }

  Widget _trashZone(ColorScheme scheme) {
    const red = Color(0xFFE5534B);
    final hot = _trashTarget;
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
        DragWatch.end();
      },
      child: DashedBox(
        color: red.withValues(alpha: hot ? 1 : 0.55),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: hot ? red.withValues(alpha: 0.30) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
        DragWatch.end();
      },
      child: DashedBox(
        color: scheme.primary.withValues(alpha: _newTarget ? 1 : 0.55),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _newTarget
                ? scheme.primary.withValues(alpha: 0.30)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
                _action(Icons.picture_as_pdf_outlined, 'Gerar PDF',
                    () => _run(s, 'Gerando PDF…', BulkRunner.makePdf), scheme),
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
    return MouseRegion(
      onEnter: (ev) => PreviewController.i.hover(path, ev.position),
      onExit: (_) => PreviewController.i.unhover(path),
      child: Container(
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
    return MouseRegion(
      // Preview ao pairar (igual à lista da pasta).
      onEnter: (ev) => PreviewController.i.hover(path, ev.position),
      onExit: (_) => PreviewController.i.unhover(path),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(iconForName(name), size: 18, color: colorForName(name, scheme)),
          const SizedBox(width: 8),
          Expanded(
            child: renaming
                ? const MagicName(width: 120)
                : GestureDetector(
                    onTap: () => launchUrl(Uri.file(path)),
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
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
      ),
    );
  }

  Widget _deck(List<String> paths, double size, ColorScheme scheme,
      {bool holo = false}) {
    return FileCardDeck(paths: paths, height: size, holo: holo);
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
