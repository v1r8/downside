import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ai.dart';
import 'stacks.dart';

/// Uma pilha arquivada no fichário (histórico permanente).
class ArchivedStack {
  ArchivedStack(this.id, this.title, this.paths, this.date,
      {this.favorite = false});
  final String id;
  String title;
  final List<String> paths;
  final DateTime date;
  bool favorite;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'paths': paths,
        'date': date.toIso8601String(),
        'favorite': favorite,
      };

  static ArchivedStack? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final paths = (j['paths'] as List?)?.whereType<String>().toList();
    final date = DateTime.tryParse(j['date'] as String? ?? '');
    if (id == null || paths == null || date == null) return null;
    return ArchivedStack(
      id,
      (j['title'] as String?) ?? 'Pilha',
      paths,
      date,
      favorite: (j['favorite'] as bool?) ?? false,
    );
  }
}

/// Fichário: histórico persistente de pilhas. Portado do StackHistory
/// do Mac (títulos por IA entram no bloco seguinte).
class FicharioStore {
  FicharioStore._();
  static final FicharioStore i = FicharioStore._();

  final archived = ValueNotifier<List<ArchivedStack>>([]);

  /// Fichas com título sendo gerado pela IA (efeito de carregamento).
  final naming = ValueNotifier<Set<String>>({});
  bool _loaded = false;

  String get _dir {
    final appdata = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dir = p.join(appdata, 'Downside', 'Fichario');
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  String get _store => p.join(_dir, 'historico.json');

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = File(_store);
      if (!f.existsSync()) return;
      final raw = jsonDecode(f.readAsStringSync()) as List;
      archived.value = raw
          .whereType<Map<String, dynamic>>()
          .map(ArchivedStack.fromJson)
          .whereType<ArchivedStack>()
          .toList();
    } catch (_) {}
  }

  void archive(FileStack s) {
    ensureLoaded();
    final entry = ArchivedStack(
      DateTime.now().microsecondsSinceEpoch.toString(),
      _dateTitle(),
      [...s.paths],
      DateTime.now(),
    );
    archived.value = [entry, ...archived.value];
    _save();
    _nameWithAI(entry);
  }

  /// Gera o título pela IA em segundo plano (Ollama -> Claude); se não
  /// houver IA, mantém o título por data.
  Future<void> _nameWithAI(ArchivedStack entry) async {
    naming.value = {...naming.value, entry.id};
    try {
      final title = await AINamer.titleFor(entry.paths);
      if (title != null && title.isNotEmpty) rename(entry.id, title);
    } catch (_) {}
    naming.value = {...naming.value}..remove(entry.id);
  }

  void delete(String id) {
    archived.value = archived.value.where((e) => e.id != id).toList();
    _save();
  }

  void toggleFavorite(String id) {
    final list = [...archived.value];
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    list[idx].favorite = !list[idx].favorite;
    archived.value = list;
    _save();
  }

  void rename(String id, String title) {
    final list = [...archived.value];
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    list[idx].title = title;
    archived.value = list;
    _save();
  }

  /// (Re)gera o título pela IA local (Ollama -> Claude) sob demanda.
  Future<void> regenerateTitle(String id) async {
    final idx = archived.value.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    await _nameWithAI(archived.value[idx]);
  }

  void deleteMany(Iterable<String> ids) {
    final set = ids.toSet();
    archived.value = archived.value.where((e) => !set.contains(e.id)).toList();
    _save();
  }

  String _dateTitle() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Pilha ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  void _save() {
    try {
      File(_store).writeAsStringSync(
          jsonEncode(archived.value.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
