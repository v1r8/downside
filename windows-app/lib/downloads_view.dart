import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:watcher/watcher.dart';

import 'clipboard.dart';
import 'file_card.dart';
import 'magic_name.dart';
import 'prefs.dart';
import 'preview.dart';
import 'search.dart';
import 'smart_names.dart';
import 'win_shell.dart';

class _Entry {
  _Entry(this.path, this.name, this.isDir, this.modified, this.size,
      {this.isClip = false});
  final String path;
  final String name;
  final bool isDir;
  final DateTime modified;
  final int size;
  final bool isClip;
}

/// Conteudo da pasta monitorada (linha do tempo / grade / lista) com
/// multiselecao estilo Finder, menu de contexto, arrastar para fora e
/// busca em linguagem natural.
class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key, this.query = ''});

  final String query;

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  List<_Entry> _entries = [];
  final Set<String> _selection = {};
  int? _anchor;
  StreamSubscription<WatchEvent>? _watchSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _startWatching();
    Prefs.i.folder.addListener(_onFolderChanged);
    Prefs.i.viewMode.addListener(_onViewChanged);
    Prefs.i.clipboardEnabled.addListener(_onViewChanged);
    Prefs.i.clipboardMark.addListener(_onViewChanged);
    Prefs.i.smartNames.addListener(_onViewChanged);
    ClipboardMonitor.i.items.addListener(_onViewChanged);
    SmartNameStore.i.names.addListener(_onViewChanged);
    SmartNameStore.i.pending.addListener(_onViewChanged);
  }

  @override
  void dispose() {
    Prefs.i.folder.removeListener(_onFolderChanged);
    Prefs.i.viewMode.removeListener(_onViewChanged);
    Prefs.i.clipboardEnabled.removeListener(_onViewChanged);
    Prefs.i.clipboardMark.removeListener(_onViewChanged);
    Prefs.i.smartNames.removeListener(_onViewChanged);
    ClipboardMonitor.i.items.removeListener(_onViewChanged);
    SmartNameStore.i.names.removeListener(_onViewChanged);
    SmartNameStore.i.pending.removeListener(_onViewChanged);
    _watchSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFolderChanged() {
    _watchSub?.cancel();
    _startWatching();
    _load();
  }

  void _onViewChanged() => setState(() {});

  void _startWatching() {
    try {
      final watcher = DirectoryWatcher(Prefs.i.folder.value);
      _watchSub = watcher.events.listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), _load);
      });
    } catch (_) {}
  }

  /// Pasta (+ itens do clipboard, se habilitado), mais recentes primeiro.
  List<_Entry> get _all {
    if (!Prefs.i.clipboardEnabled.value) return _entries;
    final known = _entries.map((e) => e.path).toSet();
    final clips = ClipboardMonitor.i.items.value
        .where((c) => !known.contains(c.path))
        .map((c) => _Entry(c.path, c.name, false, c.date, _sizeOf(c.path),
            isClip: true));
    return [..._entries, ...clips]
      ..sort((a, b) => b.modified.compareTo(a.modified));
  }

  int _sizeOf(String path) {
    try {
      return File(path).statSync().size;
    } catch (_) {
      return 0;
    }
  }

  List<_Entry> get _visible {
    final base = _all;
    final raw = widget.query.trim();
    if (raw.isEmpty) return base;
    final q = NaturalSearch.parse(raw);
    if (q.isEmpty) return base;
    return base
        .where((e) => NaturalSearch.matches(
              name: e.name,
              isDir: e.isDir,
              size: e.size,
              date: e.modified,
              query: q,
            ))
        .toList();
  }

  void _load() {
    final dir = Directory(Prefs.i.folder.value);
    final list = <_Entry>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        try {
          final st = e.statSync();
          list.add(_Entry(e.path, name,
              st.type == FileSystemEntityType.directory, st.modified, st.size));
        } catch (_) {}
      }
    } catch (_) {}
    list.sort((a, b) => b.modified.compareTo(a.modified));
    if (mounted) {
      setState(() {
        _entries = list.take(300).toList();
        _selection.removeWhere((path) => !_entries.any((e) => e.path == path));
      });
    }
  }

  // MARK: selecao (semantica do Finder)

  void _tap(List<_Entry> items, int index) {
    final e = items[index];
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (ctrl) {
        if (!_selection.add(e.path)) _selection.remove(e.path);
        _anchor = index;
      } else if (shift && _anchor != null) {
        final lo = _anchor! < index ? _anchor! : index;
        final hi = _anchor! < index ? index : _anchor!;
        for (var k = lo; k <= hi && k < items.length; k++) {
          _selection.add(items[k].path);
        }
      } else {
        _selection
          ..clear()
          ..add(e.path);
        _anchor = index;
      }
    });
  }

  List<String> _targets(_Entry e) {
    if (_selection.contains(e.path) && _selection.length > 1) {
      return _selection.toList();
    }
    return [e.path];
  }

  Future<void> _open(List<String> paths) async {
    for (final path in paths) {
      try {
        await launchUrl(Uri.file(path));
      } catch (_) {}
    }
  }

  void _contextMenu(List<_Entry> items, int index, Offset pos) {
    final e = items[index];
    if (!_selection.contains(e.path)) {
      setState(() {
        _selection
          ..clear()
          ..add(e.path);
        _anchor = index;
      });
    }
    final targets = _targets(e);
    final suffix = targets.length > 1 ? ' (${targets.length})' : '';
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'open', child: Text('Abrir$suffix')),
        PopupMenuItem(value: 'reveal', child: const Text('Mostrar no Explorer')),
        PopupMenuItem(value: 'copy', child: Text('Copiar caminho$suffix')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'trash', child: Text('Mover para a Lixeira$suffix')),
      ],
    ).then((choice) {
      switch (choice) {
        case 'open':
          _open(targets);
          break;
        case 'reveal':
          WinShell.revealInExplorer(e.path);
          break;
        case 'copy':
          Clipboard.setData(ClipboardData(text: targets.join('\n')));
          break;
        case 'trash':
          if (WinShell.moveToRecycleBin(targets)) {
            setState(() => _selection.clear());
            _load();
          }
          break;
      }
    });
  }

  /// Envolve uma celula com arrastar-para-fora (arquivo real).
  Widget _draggable(_Entry e, Widget child) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final item = DragItem();
        item.add(Formats.fileUri(Uri.file(e.path)));
        return item;
      },
      child: DraggableWidget(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(widget.query.trim().isEmpty ? 'Pasta vazia' : 'Nada encontrado',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    switch (Prefs.i.viewMode.value) {
      case 'grid':
        return _grid(items, scheme);
      case 'list':
        return _listView(items, scheme, grouped: false);
      default:
        return _listView(items, scheme, grouped: true);
    }
  }

  Widget _grid(List<_Entry> items, ColorScheme scheme) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 112,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        SmartNameStore.i.ensureName(e.path, isDir: e.isDir);
        final cell = _cellDecoration(
          selected: _selection.contains(e.path),
          scheme: scheme,
          clipTint: e.isClip && _clipTint,
          clipBar: e.isClip && _clipBar,
          child: Column(
            children: [
              _cardLeading(e, 56, scheme),
              const SizedBox(height: 6),
              Expanded(
                child: Center(
                  child: SmartNameStore.i.isPending(e.path)
                      ? const MagicName(width: 64, center: true)
                      : Text(SmartNameStore.i.displayName(e.path, e.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        );
        return _interactive(items, i, e, cell);
      },
    );
  }

  Widget _listView(List<_Entry> items, ColorScheme scheme,
      {required bool grouped}) {
    final rows = <Object>[];
    String? current;
    for (final e in items) {
      if (grouped) {
        final b = _bucket(e.modified);
        if (b != current) {
          current = b;
          rows.add(b);
        }
      }
      rows.add(e);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        if (r is String) {
          return Padding(
            padding: EdgeInsets.only(
                left: 8, right: 8, top: i == 0 ? 6 : 16, bottom: 6),
            child: Text(r,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
          );
        }
        final e = r as _Entry;
        SmartNameStore.i.ensureName(e.path, isDir: e.isDir);
        final index = items.indexOf(e);
        final row = _cellDecoration(
          selected: _selection.contains(e.path),
          scheme: scheme,
          clipTint: e.isClip && _clipTint,
          clipBar: e.isClip && _clipBar,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _leading(e, 26, scheme),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (SmartNameStore.i.isPending(e.path))
                      const MagicName(width: 120)
                    else
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                                SmartNameStore.i.displayName(e.path, e.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          if (SmartNameStore.i.tag(e.path, e.isDir) != null) ...[
                            const SizedBox(width: 5),
                            TypeTag(SmartNameStore.i.tag(e.path, e.isDir)!),
                          ],
                        ],
                      ),
                    Text(_meta(e),
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );
        return _interactive(items, index, e, row);
      },
    );
  }

  static const Color _clipColor = Color(0xFFB388FF);

  Widget _cellDecoration({
    required bool selected,
    required ColorScheme scheme,
    required Widget child,
    required EdgeInsets padding,
    bool clipTint = false,
    bool clipBar = false,
  }) {
    final base = Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: padding,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.22)
            : clipTint
                ? _clipColor.withValues(alpha: 0.10)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
    if (!clipBar) return base;
    return Stack(
      children: [
        base,
        Positioned(
          left: 2,
          top: 6,
          bottom: 6,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: _clipColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _interactive(List<_Entry> items, int index, _Entry e, Widget child) {
    return MouseRegion(
      onEnter: (ev) => PreviewController.i.hover(e.path, ev.position),
      onExit: (_) => PreviewController.i.unhover(e.path),
      child: _draggable(
        e,
        GestureDetector(
          onTapDown: (_) {
            PreviewController.i.dismiss();
            _tap(items, index);
          },
          onDoubleTap: () => _open(_targets(e)),
          onSecondaryTapDown: (d) =>
              _contextMenu(items, index, d.globalPosition),
          child: child,
        ),
      ),
    );
  }

  // MARK: helpers

  String _bucket(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    final diff = today.difference(dd).inDays;
    if (diff <= 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (diff < 7) return 'Esta semana';
    if (d.year == now.year && d.month == now.month) return 'Este mes';
    return 'Anteriores';
  }

  String _meta(_Entry e) {
    final size = e.isDir ? 'Pasta' : _humanSize(e.size);
    return '$size - ${_relative(e.modified)}';
  }

  String _relative(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dd = DateTime(d.year, d.month, d.day);
    final diff = today.difference(dd).inDays;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    if (diff <= 0) return '$hh:$mm';
    if (diff == 1) return 'ontem';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  bool get _clipBadge =>
      Prefs.i.clipboardMark.value == 'badge';
  bool get _clipTint => Prefs.i.clipboardMark.value == 'tint';
  bool get _clipBar => Prefs.i.clipboardMark.value == 'bar';

  /// Carta do item (grade): retângulo opaco com cara de carta, miniatura
  /// real nas imagens, faixa/ícone na cor do tipo. Selo de clipboard.
  Widget _cardLeading(_Entry e, double height, ColorScheme scheme) {
    final card =
        FileCard(path: e.path, name: e.name, isDir: e.isDir, height: height);
    if (!e.isClip || !_clipBadge) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration:
                BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.content_paste,
                size: height * 0.22, color: scheme.onPrimary),
          ),
        ),
      ],
    );
  }

  /// Icone do item, com um pequeno selo de clipboard quando aplicavel.
  Widget _leading(_Entry e, double size, ColorScheme scheme) {
    final icon = Icon(_iconFor(e), size: size, color: _colorFor(e, scheme));
    if (!e.isClip || !_clipBadge) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration:
                BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.content_paste,
                size: size * 0.34, color: scheme.onPrimary),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(_Entry e) {
    if (e.isDir) return Icons.folder;
    switch (p.extension(e.name).toLowerCase()) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
      case '.heic':
        return Icons.image;
      case '.mp4':
      case '.mov':
      case '.mkv':
      case '.avi':
        return Icons.movie;
      case '.mp3':
      case '.wav':
      case '.m4a':
      case '.flac':
        return Icons.audiotrack;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return Icons.folder_zip;
      case '.xls':
      case '.xlsx':
      case '.csv':
        return Icons.table_chart;
      case '.doc':
      case '.docx':
      case '.txt':
      case '.md':
        return Icons.description;
      case '.exe':
      case '.msi':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _colorFor(_Entry e, ColorScheme scheme) {
    if (e.isDir) return const Color(0xFF6FB1FC);
    switch (p.extension(e.name).toLowerCase()) {
      case '.pdf':
        return const Color(0xFFE5534B);
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
      case '.heic':
        return const Color(0xFF55B973);
      case '.xls':
      case '.xlsx':
      case '.csv':
        return const Color(0xFF3FA06B);
      default:
        return scheme.onSurfaceVariant;
    }
  }
}
