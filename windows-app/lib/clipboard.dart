import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';

import 'clipboard_seq.dart';

class ClipItem {
  ClipItem(this.path, this.name, this.date);
  final String path;
  final String name;
  final DateTime date;

  Map<String, dynamic> toJson() =>
      {'path': path, 'name': name, 'date': date.toIso8601String()};

  static ClipItem? fromJson(Map<String, dynamic> j) {
    final path = j['path'] as String?;
    final name = j['name'] as String?;
    final date = DateTime.tryParse(j['date'] as String? ?? '');
    if (path == null || name == null || date == null) return null;
    if (!File(path).existsSync()) return null;
    return ClipItem(path, name, date);
  }
}

/// Monitora o clipboard do Windows e guarda capturas (texto/imagem) num
/// cofre do app, expondo-as para a linha do tempo. Portado do
/// ClipboardMonitor do Mac.
class ClipboardMonitor {
  ClipboardMonitor._();
  static final ClipboardMonitor i = ClipboardMonitor._();

  final items = ValueNotifier<List<ClipItem>>([]);

  Timer? _timer;
  int _lastSeq = 0;
  bool _loaded = false;
  static const int _maxItems = 50;
  static const Duration _retention = Duration(days: 30);

  String get _vault {
    final appdata = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dir = p.join(appdata, 'Downside', 'Clipboard');
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  String get _storeFile => p.join(_vault, 'itens.json');

  void start() {
    if (_timer != null) return;
    if (!_loaded) {
      _load();
      _loaded = true;
    }
    try {
      _lastSeq = clipboardSequence();
    } catch (_) {}
    _timer =
        Timer.periodic(const Duration(milliseconds: 1200), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    int seq;
    try {
      seq = clipboardSequence();
    } catch (_) {
      return;
    }
    if (seq == _lastSeq) return;
    _lastSeq = seq;

    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final reader = await clipboard.read();

    if (reader.canProvide(Formats.plainText)) {
      final text = await reader.readValue(Formats.plainText);
      if (text != null && text.trim().length > 2) {
        _saveText(text.trim());
        return;
      }
    }
    if (reader.canProvide(Formats.png)) {
      reader.getFile(Formats.png, (file) async {
        final bytes = await file.readAll();
        _saveBytes(bytes, 'png');
      });
    }
  }

  void _saveText(String text) {
    final preview =
        _sanitize(text.length > 28 ? text.substring(0, 28) : text);
    final name = preview.isEmpty ? 'Texto ${_stamp()}' : preview;
    final dest = _unique(name, 'txt');
    try {
      File(dest).writeAsStringSync(text);
      _add(dest, name);
    } catch (_) {}
  }

  void _saveBytes(Uint8List bytes, String ext) {
    final name = 'Clipboard ${_stamp()}';
    final dest = _unique(name, ext);
    try {
      File(dest).writeAsBytesSync(bytes);
      _add(dest, name);
    } catch (_) {}
  }

  void _add(String path, String name) {
    final next = [ClipItem(path, name, DateTime.now()), ...items.value];
    _pruneInto(next);
    items.value = next;
    _save();
  }

  /// Expira antigos (30 dias) e limita a 50, apagando os arquivos.
  void _pruneInto(List<ClipItem> list) {
    final cutoff = DateTime.now().subtract(_retention);
    list.removeWhere((c) {
      if (c.date.isBefore(cutoff)) {
        _tryDelete(c.path);
        return true;
      }
      return false;
    });
    while (list.length > _maxItems) {
      final removed = list.removeLast();
      _tryDelete(removed.path);
    }
  }

  void _tryDelete(String path) {
    if (!path.startsWith(_vault)) return; // nunca apaga arquivos de fora
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _load() {
    try {
      final f = File(_storeFile);
      if (!f.existsSync()) return;
      final raw = jsonDecode(f.readAsStringSync()) as List;
      final loaded = raw
          .whereType<Map<String, dynamic>>()
          .map(ClipItem.fromJson)
          .whereType<ClipItem>()
          .toList();
      _pruneInto(loaded);
      items.value = loaded;
    } catch (_) {}
  }

  void _save() {
    try {
      File(_storeFile)
          .writeAsStringSync(jsonEncode(items.value.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

  String _sanitize(String s) => s
      .replaceAll('/', ' ')
      .replaceAll(r'\', ' ')
      .replaceAll(':', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('*', ' ')
      .replaceAll('?', ' ')
      .replaceAll('"', ' ')
      .replaceAll('<', ' ')
      .replaceAll('>', ' ')
      .replaceAll('|', ' ')
      .trim();

  String _stamp() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}.${two(d.second)}';
  }

  String _unique(String name, String ext) {
    var candidate = p.join(_vault, '$name.$ext');
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(_vault, '$name $n.$ext');
      n++;
    }
    return candidate;
  }
}
