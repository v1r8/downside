import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'file_icons.dart';
import 'file_text.dart';
import 'prefs.dart';

class PreviewState {
  PreviewState(this.path, this.anchor);
  final String path;
  final Offset anchor; // coordenadas locais da janela
}

/// Preview ao pairar (hover) — mostra um cartão flutuante perto do item
/// após um atraso configurável. Portado do PreviewController do Mac
/// (versão Windows: o cartão aparece sobre o painel).
class PreviewController {
  PreviewController._();
  static final PreviewController i = PreviewController._();

  final state = ValueNotifier<PreviewState?>(null);
  Timer? _timer;
  String? _pending;

  void hover(String path, Offset anchor) {
    if (!Prefs.i.hoverEnabled.value) return;
    if (state.value?.path == path) return;
    _pending = path;
    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: Prefs.i.hoverDelay.value),
      () {
        _pending = null;
        state.value = PreviewState(path, anchor);
      },
    );
  }

  void unhover(String path) {
    if (_pending == path) {
      _timer?.cancel();
      _pending = null;
    }
    if (state.value?.path == path) state.value = null;
  }

  void dismiss() {
    _timer?.cancel();
    _pending = null;
    if (state.value != null) state.value = null;
  }
}

/// Camada que desenha o cartão de preview (fica no topo do painel).
class PreviewLayer extends StatelessWidget {
  const PreviewLayer({super.key});

  static const double _w = 280;
  static const double _h = 240;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PreviewState?>(
      valueListenable: PreviewController.i.state,
      builder: (context, st, _) {
        if (st == null) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(context);
        var left = st.anchor.dx + 18;
        if (left + _w > size.width - 8) left = st.anchor.dx - _w - 18;
        if (left < 8) left = 8;
        var top = st.anchor.dy - _h / 2;
        final maxTop = (size.height - _h - 8);
        top = top.clamp(8.0, maxTop > 8 ? maxTop : 8.0);
        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: _PreviewCard(key: ValueKey(st.path), path: st.path),
          ),
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({super.key, required this.path});
  final String path;

  static const _imageExt = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
  static const _textExt = {
    '.txt', '.md', '.json', '.xml', '.log', '.yaml', '.yml', '.ini',
    '.dart', '.py', '.js', '.ts', '.html', '.css', '.sql', '.sh'
  };
  static const _tableExt = {'.csv', '.tsv'};
  static const _docExt = {'.pdf', '.docx', '.pptx', '.xlsx'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: Container(
        width: PreviewLayer._w,
        height: PreviewLayer._h,
        decoration: BoxDecoration(
          color: const Color(0xF21E1E24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _body(scheme)),
            _footer(scheme),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    final ext = p.extension(path).toLowerCase();
    if (FileSystemEntity.isDirectorySync(path)) return _folder(scheme);
    if (_imageExt.contains(ext)) {
      return Image.file(File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _generic(scheme));
    }
    if (_tableExt.contains(ext)) return _table(scheme);
    if (_textExt.contains(ext)) return _text(scheme);
    if (_docExt.contains(ext)) return _extracted(scheme);
    return _generic(scheme);
  }

  /// PDF / Office: mostra o conteúdo extraído (texto aproximado).
  Widget _extracted(ColorScheme scheme) {
    return FutureBuilder<String>(
      future: FileText.snippet(path, max: 1600),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: scheme.onSurfaceVariant),
            ),
          );
        }
        final text = (snap.data ?? '').trim();
        if (text.isEmpty) return _generic(scheme);
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(iconForName(p.basename(path)),
                      size: 14, color: colorForName(p.basename(path), scheme)),
                  const SizedBox(width: 6),
                  Text('Conteúdo',
                      style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(text,
                    maxLines: 11,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, height: 1.35)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// CSV/TSV: mini-tabela (até 30 linhas × 6 colunas).
  Widget _table(ColorScheme scheme) {
    return FutureBuilder<List<List<String>>>(
      future: _readRows(),
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null || rows.isEmpty) return _generic(scheme);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var r = 0; r < rows.length; r++)
                  Row(
                    children: [
                      for (final cell in rows[r])
                        SizedBox(
                          width: 92,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 3),
                            child: Text(cell,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: r == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<List<String>>> _readRows() async {
    try {
      final raw = await File(path).readAsString();
      final lines = raw
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty)
          .take(30)
          .toList();
      if (lines.isEmpty) return [];
      // Detecta o separador pela primeira linha.
      final first = lines.first;
      final tabs = '\t'.allMatches(first).length;
      final semis = ';'.allMatches(first).length;
      final commas = ','.allMatches(first).length;
      final sep = (tabs >= semis && tabs >= commas)
          ? '\t'
          : (semis >= commas ? ';' : ',');
      return lines.map((l) => l.split(sep).take(6).toList()).toList();
    } catch (_) {
      return [];
    }
  }

  Widget _text(ColorScheme scheme) {
    return FutureBuilder<String>(
      future: _readHead(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _generic(scheme);
        }
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            snap.data!,
            maxLines: 12,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, height: 1.35, fontFamily: 'Consolas'),
          ),
        );
      },
    );
  }

  Future<String> _readHead() async {
    try {
      final raw = await File(path).readAsString();
      return raw.length > 1500 ? raw.substring(0, 1500) : raw;
    } catch (_) {
      return '';
    }
  }

  Widget _folder(ColorScheme scheme) {
    List<String> names = [];
    try {
      names = Directory(path)
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => !n.startsWith('.'))
          .take(8)
          .toList();
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in names)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Icon(iconForName(n), size: 14, color: colorForName(n, scheme)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(n,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _generic(ColorScheme scheme) {
    return Center(
      child: Icon(
        iconForName(p.basename(path),
            isDir: FileSystemEntity.isDirectorySync(path)),
        size: 72,
        color: colorForName(p.basename(path), scheme),
      ),
    );
  }

  Widget _footer(ColorScheme scheme) {
    String meta = '';
    try {
      final st = File(path).statSync();
      meta = _humanSize(st.size);
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.white.withValues(alpha: 0.04),
      child: Row(
        children: [
          Expanded(
            child: Text(p.basename(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          if (meta.isNotEmpty)
            Text(meta,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
