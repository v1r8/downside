import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'file_icons.dart';
import 'file_text.dart';
import 'prefs.dart';

const _imageExt = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
const _tableExt = {'.csv', '.tsv'};
const _docExt = {'.pdf', '.docx', '.pptx', '.xlsx'};

/// Tipos interativos (recebem mouse: rolar PDF, editar texto, rolar tabela).
/// Imagem/pasta/genérico continuam "click-through".
bool _isInteractive(String path) {
  if (FileSystemEntity.isDirectorySync(path)) return false;
  final ext = p.extension(path).toLowerCase();
  return ext == '.pdf' || _tableExt.contains(ext) || _editableExt.contains(ext);
}

const _editableExt = {
  '.txt', '.md', '.json', '.xml', '.log', '.yaml', '.yml', '.ini',
  '.dart', '.py', '.js', '.ts', '.html', '.css', '.sql', '.sh'
};

class PreviewState {
  PreviewState(this.path, this.anchor);
  final String path;
  final Offset anchor; // coordenadas locais da janela
}

/// Preview ao pairar (hover) — cartão flutuante interativo posicionado ao
/// lado do item. PDF rolável/zoom, texto editável (autosave), CSV em
/// tabela. Espelha o PreviewController do Mac (por ora dentro da janela;
/// a versão em janela separada vem em seguida).
class PreviewController {
  PreviewController._();
  static final PreviewController i = PreviewController._();

  final state = ValueNotifier<PreviewState?>(null);
  Timer? _timer;
  Timer? _dismissTimer;
  String? _pending;

  void hover(String path, Offset anchor) {
    if (!Prefs.i.hoverEnabled.value) return;
    _dismissTimer?.cancel();
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
    // Carência: mover o mouse para cima do preview cancela o fechamento.
    if (state.value?.path == path) scheduleDismiss();
  }

  /// Mouse entrou no cartão de preview — não fecha enquanto interage.
  void keepOpen() => _dismissTimer?.cancel();

  void scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 260), () {
      if (state.value != null) state.value = null;
    });
  }

  void dismiss() {
    _timer?.cancel();
    _dismissTimer?.cancel();
    _pending = null;
    if (state.value != null) state.value = null;
  }
}

/// Camada que desenha o cartão de preview (fica no topo do painel).
class PreviewLayer extends StatelessWidget {
  const PreviewLayer({super.key});

  static const double _w = 360;
  static const double _h = 420;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PreviewState?>(
      valueListenable: PreviewController.i.state,
      builder: (context, st, _) {
        if (st == null) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(context);
        // Preferência: à ESQUERDA do item; se não couber, à direita.
        var left = st.anchor.dx - _w - 18;
        if (left < 8) {
          final right = st.anchor.dx + 18;
          left = (right + _w > size.width - 8) ? 8 : right;
        }
        var top = st.anchor.dy - _h / 2;
        final maxTop = size.height - _h - 8;
        top = top.clamp(8.0, maxTop > 8 ? maxTop : 8.0);
        final interactive = _isInteractive(st.path);
        final card = _PreviewCard(key: ValueKey(st.path), path: st.path);
        return Positioned(
          left: left,
          top: top,
          width: _w,
          height: _h,
          child: interactive
              ? MouseRegion(
                  onEnter: (_) => PreviewController.i.keepOpen(),
                  onExit: (_) => PreviewController.i.scheduleDismiss(),
                  child: card,
                )
              : IgnorePointer(child: card),
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
      ),
      child: Container(
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
      return InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.file(File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _generic(scheme)),
        ),
      );
    }
    if (ext == '.pdf') return _PdfBody(path: path);
    if (_tableExt.contains(ext)) return _table(scheme);
    if (_editableExt.contains(ext)) return _TextEditor(path: path);
    if (_docExt.contains(ext)) return _extracted(scheme);
    return _generic(scheme);
  }

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
                    strokeWidth: 2, color: scheme.onSurfaceVariant)),
          );
        }
        final text = (snap.data ?? '').trim();
        if (text.isEmpty) return _generic(scheme);
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Text(text,
              maxLines: 22,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.35)),
        );
      },
    );
  }

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
                          width: 96,
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
          .take(60)
          .toList();
      if (lines.isEmpty) return [];
      final first = lines.first;
      final tabs = '\t'.allMatches(first).length;
      final semis = ';'.allMatches(first).length;
      final commas = ','.allMatches(first).length;
      final sep = (tabs >= semis && tabs >= commas)
          ? '\t'
          : (semis >= commas ? ';' : ',');
      return lines.map((l) => l.split(sep).take(8).toList()).toList();
    } catch (_) {
      return [];
    }
  }

  Widget _folder(ColorScheme scheme) {
    List<String> names = [];
    try {
      names = Directory(path)
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => !n.startsWith('.'))
          .take(14)
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
      meta = _humanSize(File(path).statSync().size);
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.white.withValues(alpha: 0.04),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => launchUrl(Uri.file(path)),
              child: Text(p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
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

/// PDF interativo: documento inteiro com rolagem e zoom (pdfx).
class _PdfBody extends StatefulWidget {
  const _PdfBody({required this.path});
  final String path;

  @override
  State<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends State<_PdfBody> {
  PdfControllerPinch? _ctrl;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      _ctrl = PdfControllerPinch(
          document: PdfDocument.openFile(widget.path));
    } catch (_) {
      _failed = true;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_failed || _ctrl == null) {
      return Center(
        child: Icon(Icons.picture_as_pdf,
            size: 72, color: colorForName('a.pdf', scheme)),
      );
    }
    return PdfViewPinch(
      controller: _ctrl!,
      onDocumentError: (_) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }
}

/// Editor de texto com autosave (debounce 800ms, escrita atômica, e pula
/// o save se o arquivo mudou no disco desde a abertura).
class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.path});
  final String path;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  final _ctrl = TextEditingController();
  Timer? _save;
  bool _loaded = false;
  bool _readonly = false;
  DateTime? _loadedMtime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = File(widget.path);
      final st = f.statSync();
      if (st.size > 2 * 1024 * 1024) {
        _readonly = true;
      }
      final text = await f.readAsString();
      _loadedMtime = st.modified;
      _ctrl.text = text;
    } catch (_) {
      _readonly = true;
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _onChanged(String _) {
    if (_readonly) return;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 800), _write);
  }

  Future<void> _write() async {
    try {
      final f = File(widget.path);
      // Não sobrescreve se mudou no disco desde a abertura.
      if (_loadedMtime != null && f.statSync().modified.isAfter(_loadedMtime!)) {
        return;
      }
      final tmp = File('${widget.path}.tmp_downside');
      await tmp.writeAsString(_ctrl.text, flush: true);
      await tmp.rename(widget.path);
      _loadedMtime = File(widget.path).statSync().modified;
    } catch (_) {}
  }

  @override
  void dispose() {
    _save?.cancel();
    if (!_readonly) _write();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _ctrl,
        onChanged: _onChanged,
        readOnly: _readonly,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontSize: 11.5, height: 1.35, fontFamily: 'Consolas'),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: _readonly ? 'Somente leitura' : null,
        ),
      ),
    );
  }
}
