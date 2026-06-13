import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:watcher/watcher.dart';

import 'prefs.dart';
import 'search.dart';
import 'win_shell.dart';

class _Entry {
  _Entry(this.path, this.name, this.isDir, this.modified, this.size);
  final String path;
  final String name;
  final bool isDir;
  final DateTime modified;
  final int size;
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
  }

  @override
  void dispose() {
    Prefs.i.folder.removeListener(_onFolderChanged);
    Prefs.i.viewMode.removeListener(_onViewChanged);
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

  List<_Entry> get _visible {
    final raw = widget.query.trim();
    if (raw.isEmpty) return _entries;
    final q = NaturalSearch.parse(raw);
    if (q.isEmpty) return _entries;
    return _entries
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
        final cell = _cellDecoration(
          selected: _selection.contains(e.path),
          scheme: scheme,
          child: Column(
            children: [
              Icon(_iconFor(e), size: 40, color: _colorFor(e, scheme)),
              const SizedBox(height: 6),
              Expanded(
                child: Text(e.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11)),
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
        final index = items.indexOf(e);
        final row = _cellDecoration(
          selected: _selection.contains(e.path),
          scheme: scheme,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(_iconFor(e), size: 26, color: _colorFor(e, scheme)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5)),
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

  Widget _cellDecoration({
    required bool selected,
    required ColorScheme scheme,
    required Widget child,
    required EdgeInsets padding,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: padding,
      decoration: BoxDecoration(
        color:
            selected ? scheme.primary.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }

  Widget _interactive(List<_Entry> items, int index, _Entry e, Widget child) {
    return _draggable(
      e,
      GestureDetector(
        onTap: () => _tap(items, index),
        onDoubleTap: () => _open(_targets(e)),
        onSecondaryTapDown: (d) => _contextMenu(items, index, d.globalPosition),
        child: child,
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
