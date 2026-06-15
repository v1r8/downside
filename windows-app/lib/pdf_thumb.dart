import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

/// Miniatura da 1ª página de um PDF, com cache LRU + dedupe de pedidos +
/// limite de concorrência (evita renderizar dezenas de PDFs ao mesmo
/// tempo numa pasta cheia). Usado pelas cartas (FileCard).
class PdfThumbService {
  PdfThumbService._();
  static final PdfThumbService i = PdfThumbService._();

  static const int _cap = 80;
  static const int _maxActive = 3;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();

  Future<Uint8List?> thumbnail(String path, {int width = 220}) {
    var mtime = 0;
    try {
      mtime = File(path).statSync().modified.millisecondsSinceEpoch;
    } catch (_) {}
    final key = '$path|$mtime|$width';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // marca como recém-usado (LRU)
      return Future.value(cached);
    }
    final existing = _inflight[key];
    if (existing != null) return existing;
    final fut = _render(path, width, key);
    _inflight[key] = fut;
    return fut;
  }

  Future<Uint8List?> _render(String path, int width, String key) async {
    await _acquire();
    PdfDocument? doc;
    PdfPage? page;
    try {
      doc = await PdfDocument.openFile(path);
      page = await doc.getPage(1);
      final ratio = page.width <= 0 ? 1.4 : page.height / page.width;
      final h = (width * ratio).round();
      final img = await page.render(
        width: width.toDouble(),
        height: h.toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      final bytes = img?.bytes;
      if (bytes != null) _put(key, bytes);
      return bytes;
    } catch (_) {
      return null;
    } finally {
      try {
        await page?.close();
      } catch (_) {}
      try {
        await doc?.close();
      } catch (_) {}
      _inflight.remove(key);
      _release();
    }
  }

  void _put(String key, Uint8List bytes) {
    _cache[key] = bytes;
    while (_cache.length > _cap) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<void> _acquire() {
    if (_active < _maxActive) {
      _active++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future; // ao acordar, herda o slot (sem incrementar)
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _active--;
    }
  }
}
