import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:watcher/watcher.dart';

import 'prefs.dart';

class _Entry {
  _Entry(this.path, this.name, this.isDir, this.modified, this.size);
  final String path;
  final String name;
  final bool isDir;
  final DateTime modified;
  final int size;
}

/// Conteúdo da pasta monitorada, em três modos: linha do tempo
/// (padrão, agrupada por data), grade e lista. Abre no duplo-clique e
/// acompanha mudanças da pasta.
class DownloadsView extends StatefulWidget {
  const DownloadsView({super.key, this.query = ''});

  final String query;

  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  List<_Entry> _entries = [];
  String? _selected;
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
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
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
          list.add(_Entry(
            e.path,
            name,
            st.type == FileSystemEntityType.directory,
            st.modified,
            st.size,
          ));
        } catch (_) {}
      }
    } catch (_) {}
    list.sort((a, b) => b.modified.compareTo(a.modified));
    if (mounted) setState(() => _entries = list.take(300).toList());
  }

  Future<void> _open(_Entry e) async {
    try {
      await launchUrl(Uri.file(e.path));
    } catch (_) {}
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
        return _list(items, scheme);
      default:
        return _timeline(items, scheme);
    }
  }

  // MARK: grade

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
        final selected = _selected == e.path;
        return GestureDetector(
          onTap: () => setState(() => _selected = e.path),
          onDoubleTap: () => _open(e),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
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
          ),
        );
      },
    );
  }

  // MARK: lista (plana) e linha do tempo (agrupada por data)

  Widget _list(List<_Entry> items, ColorScheme scheme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      itemCount: items.length,
      itemBuilder: (context, i) => _row(items[i], scheme),
    );
  }

  Widget _timeline(List<_Entry> items, ColorScheme scheme) {
    // Lista achatada: cabeçalhos (String) + itens (_Entry), na ordem.
    final rows = <Object>[];
    String? current;
    for (final e in items) {
      final b = _bucket(e.modified);
      if (b != current) {
        current = b;
        rows.add(b);
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
            padding: EdgeInsets.only(left: 8, right: 8, top: i == 0 ? 6 : 16, bottom: 6),
            child: Text(r,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
          );
        }
        return _row(r as _Entry, scheme);
      },
    );
  }

  Widget _row(_Entry e, ColorScheme scheme) {
    final selected = _selected == e.path;
    return GestureDetector(
      onTap: () => setState(() => _selected = e.path),
      onDoubleTap: () => _open(e),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
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
    if (d.year == now.year && d.month == now.month) return 'Este mês';
    return 'Anteriores';
  }

  String _meta(_Entry e) {
    final size = e.isDir ? 'Pasta' : _humanSize(e.size);
    return '$size · ${_relative(e.modified)}';
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
