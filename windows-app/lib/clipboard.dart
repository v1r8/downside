import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';

import 'clipboard_seq.dart';
import 'prefs.dart';

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

  /// Padrões de texto com cara de segredo (chaves/tokens/senhas) — não são
  /// capturados quando a opção de segurança está ligada.
  static final List<RegExp> _secretRes = [
    RegExp(r'\b(sk|pk|rk)-[A-Za-z0-9]{16,}'), // OpenAI/Stripe-like
    RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}'), // GitHub token
    RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}'),
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'), // AWS access key id
    RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}'), // Slack
    RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{6,}'), // JWT
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'), // PEM
  ];

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
        final trimmed = text.trim();
        if (Prefs.i.clipboardSkipSecretLike.value && _looksSecret(trimmed)) {
          return; // não guarda segredos
        }
        _saveText(trimmed);
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

  /// Expira antigos (retenção configurável; 0 = nunca) e limita a 50,
  /// apagando os arquivos.
  void _pruneInto(List<ClipItem> list) {
    final hours = Prefs.i.clipboardRetentionHours.value;
    if (hours > 0) {
      final cutoff = DateTime.now().subtract(Duration(hours: hours));
      list.removeWhere((c) {
        if (c.date.isBefore(cutoff)) {
          _tryDelete(c.path);
          return true;
        }
        return false;
      });
    }
    while (list.length > _maxItems) {
      final removed = list.removeLast();
      _tryDelete(removed.path);
    }
  }

  /// Apaga todo o histórico do clipboard (arquivos do cofre + lista).
  void clearAll() {
    for (final c in items.value) {
      _tryDelete(c.path);
    }
    items.value = [];
    _save();
  }

  bool _looksSecret(String text) {
    if (text.length > 4000) return false; // documento longo, não um segredo
    for (final re in _secretRes) {
      if (re.hasMatch(text)) return true;
    }
    // Token único, longo e de alta entropia (sem espaços, letras+dígitos).
    if (!text.contains(RegExp(r'\s')) &&
        text.length >= 32 &&
        text.length <= 200 &&
        RegExp(r'^[A-Za-z0-9_\-.=+/]+$').hasMatch(text) &&
        RegExp(r'[0-9]').hasMatch(text) &&
        RegExp(r'[A-Za-z]').hasMatch(text)) {
      return true;
    }
    return false;
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
