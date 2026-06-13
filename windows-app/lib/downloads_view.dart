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

/// Grade da pasta de Downloads: lista os arquivos (mais recentes
/// primeiro), abre no duplo-clique e acompanha mudanças da pasta.
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
  }

  @override
  void dispose() {
    Prefs.i.folder.removeListener(_onFolderChanged);
    _watchSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFolderChanged() {
    _watchSub?.cancel();
    _startWatching();
    _load();
  }

  void _startWatching() {
    try {
      final watcher = DirectoryWatcher(Prefs.i.folder.value);
      _watchSub = watcher.events.listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), _load);
      });
    } catch (_) {
      // Sem watcher: a lista ainda recarrega ao reabrir o painel.
    }
  }

  /// Recarrega de fora (ex.: cada vez que o painel é aberto).
  void reload() => _load();

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
    if (mounted) {
      setState(() => _entries = list.take(300).toList());
    }
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
            Text(widget.query.trim().isEmpty
                ? 'Pasta vazia'
                : 'Nada encontrado',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
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
                  child: Text(
                    e.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
