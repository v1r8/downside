import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ai.dart';
import 'prefs.dart';

/// Apelidos de IA para arquivos (só visuais — nada é renomeado no
/// disco). Fila processada um a um; mostra o efeito mágico enquanto
/// nomeia. Portado do SmartNames do Mac.
class SmartNameStore {
  SmartNameStore._();
  static final SmartNameStore i = SmartNameStore._();

  final names = ValueNotifier<Map<String, String>>({});
  final pending = ValueNotifier<Set<String>>({});

  final Set<String> _attempted = {};
  final List<String> _queue = [];
  bool _working = false;
  bool _loaded = false;

  String get _file {
    final appdata = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dir = p.join(appdata, 'Downside', 'SmartNames');
    Directory(dir).createSync(recursive: true);
    return p.join(dir, 'nomes.json');
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = File(_file);
      if (!f.existsSync()) return;
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      names.value = raw.map((k, v) => MapEntry(k, v as String));
    } catch (_) {}
  }

  void _save() {
    try {
      File(_file).writeAsStringSync(jsonEncode(names.value));
    } catch (_) {}
  }

  /// Pede um apelido se ainda não houver (chamado pelas células visíveis).
  void ensureName(String path, {required bool isDir}) {
    if (!Prefs.i.smartNames.value || isDir) return;
    _ensureLoaded();
    if (names.value.containsKey(path) ||
        _attempted.contains(path) ||
        _queue.contains(path)) {
      return;
    }
    _attempted.add(path);
    _queue.add(path);
    _kick();
  }

  Future<void> _kick() async {
    if (_working || _queue.isEmpty) return;
    _working = true;
    while (_queue.isNotEmpty) {
      final path = _queue.removeAt(0);
      if (!File(path).existsSync()) continue;
      pending.value = {...pending.value, path};
      String? name;
      try {
        name = await AINamer.nameForFile(path);
      } catch (_) {}
      pending.value = {...pending.value}..remove(path);
      if (name != null && name.isNotEmpty) {
        names.value = {...names.value, path: name};
      }
    }
    _save();
    _working = false;
  }

  bool isPending(String path) => pending.value.contains(path);

  /// Nome exibido: apelido da IA, ou o nome original sem a extensão
  /// (que vira a etiqueta de tipo).
  String displayName(String path, String original) {
    if (!Prefs.i.smartNames.value) return original;
    final n = names.value[path];
    if (n != null) return n;
    final ext = p.extension(original);
    if (ext.isNotEmpty && original.length > ext.length) {
      return original.substring(0, original.length - ext.length);
    }
    return original;
  }

  /// Etiqueta de tipo (PDF, PNG, …) à direita do nome.
  String? tag(String path, bool isDir) {
    if (!Prefs.i.smartNames.value || isDir) return null;
    final ext = p.extension(path);
    if (ext.isEmpty) return null;
    return ext.substring(1).toUpperCase();
  }

  void reset() {
    names.value = {};
    _attempted.clear();
    _save();
  }
}
