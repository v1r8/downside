import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ai.dart';

/// Uma pilha temporaria (deck de cartas): conjunto de arquivos reunido
/// por arrasto. Ate 3 ao mesmo tempo. Portado das pilhas do Mac.
class FileStack {
  FileStack(this.id, this.paths, {this.outputs = const {}, this.name});
  final int id;
  final List<String> paths;
  final Set<String> outputs;

  /// Nome dado pela IA local (Ollama) — opcional; quando nulo a pilha
  /// e exibida pela contagem de arquivos.
  final String? name;

  bool get hadBulkAction => outputs.isNotEmpty;
}

class StacksController {
  StacksController._();
  static final StacksController i = StacksController._();

  static const int maxStacks = 3;

  final stacks = ValueNotifier<List<FileStack>>([]);

  /// Pilhas com nome sendo gerado pela IA (efeito de carregamento no chip).
  final naming = ValueNotifier<Set<int>>({});

  /// Arquivos sendo renomeados no disco pela IA (efeito magico na linha).
  final renaming = ValueNotifier<Set<String>>({});

  int _nextId = 1;

  /// Cria uma nova pilha com os arquivos (dedup). Se ja houver 3,
  /// adiciona na ultima. Dispara a nomeacao por IA em segundo plano.
  void createWith(List<String> paths) {
    final clean = paths.where((p) => p.trim().isNotEmpty).toSet().toList();
    if (clean.isEmpty) return;
    final list = [...stacks.value];
    int targetId;
    if (list.length >= maxStacks) {
      final last = list.last;
      final merged = {...last.paths, ...clean}.toList();
      list[list.length - 1] =
          FileStack(last.id, merged, outputs: last.outputs, name: last.name);
      targetId = last.id;
    } else {
      targetId = _nextId++;
      list.add(FileStack(targetId, clean));
    }
    stacks.value = list;
    _autoName(targetId);
  }

  void addTo(int id, List<String> paths) {
    final list = [...stacks.value];
    final idx = list.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final merged = {...list[idx].paths, ...paths}.toList();
    list[idx] = FileStack(id, merged, outputs: list[idx].outputs, name: list[idx].name);
    stacks.value = list;
    // Conteudo mudou: regera o nome se ainda nao houver um definido.
    if (list[idx].name == null) _autoName(id);
  }

  void removeFromStack(int id, String path) {
    final list = [...stacks.value];
    final idx = list.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final paths = [...list[idx].paths]..remove(path);
    if (paths.isEmpty) {
      list.removeAt(idx);
    } else {
      list[idx] = FileStack(id, paths,
          outputs: {...list[idx].outputs}..remove(path), name: list[idx].name);
    }
    stacks.value = list;
  }

  void clearStack(int id) {
    stacks.value = stacks.value.where((s) => s.id != id).toList();
  }

  void addOutput(int id, String path) {
    final list = [...stacks.value];
    final idx = list.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final paths = [...list[idx].paths];
    if (!paths.contains(path)) paths.add(path);
    list[idx] = FileStack(id, paths,
        outputs: {...list[idx].outputs, path}, name: list[idx].name);
    stacks.value = list;
  }

  void setName(int id, String name) {
    final list = [...stacks.value];
    final idx = list.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final cur = list[idx];
    list[idx] = FileStack(id, cur.paths, outputs: cur.outputs, name: name);
    stacks.value = list;
  }

  /// Gera (ou regera) o nome da pilha pela IA local (Ollama -> Claude).
  Future<void> _autoName(int id) async {
    final cur = _byId(id);
    if (cur == null) return;
    naming.value = {...naming.value, id};
    try {
      final t = await AINamer.titleFor(cur.paths);
      if (t != null && t.isNotEmpty) setName(id, t);
    } catch (_) {}
    naming.value = {...naming.value}..remove(id);
  }

  /// Pedido explicito de renomear a pilha (botao na ficha aberta).
  Future<void> renameStackWithAI(int id) => _autoName(id);

  /// Renomeia UM arquivo no disco usando a IA local (mantem a extensao).
  /// Retorna true se renomeou. Recuperavel manualmente (so renomeia).
  Future<bool> renameFileOnDisk(int id, String oldPath) async {
    renaming.value = {...renaming.value, oldPath};
    var ok = false;
    try {
      final raw = await AINamer.nameForFile(oldPath);
      if (raw != null && raw.trim().isNotEmpty) {
        final newPath = await _doRename(oldPath, raw);
        if (newPath != null && newPath != oldPath) {
          _replacePath(id, oldPath, newPath);
          ok = true;
        }
      }
    } catch (_) {}
    renaming.value = {...renaming.value}..remove(oldPath);
    return ok;
  }

  /// Renomeia todos os arquivos (originais) da pilha pela IA, um a um.
  Future<int> renameAllWithAI(int id) async {
    final cur = _byId(id);
    if (cur == null) return 0;
    final targets = cur.paths.where((x) => !cur.outputs.contains(x)).toList();
    var count = 0;
    for (final path in targets) {
      // Reobtem o caminho atual (pode ter mudado em iteracoes anteriores).
      if (await renameFileOnDisk(id, path)) count++;
    }
    return count;
  }

  FileStack? _byId(int id) {
    final idx = stacks.value.indexWhere((s) => s.id == id);
    return idx < 0 ? null : stacks.value[idx];
  }

  Future<String?> _doRename(String oldPath, String rawName) async {
    try {
      final f = File(oldPath);
      if (!f.existsSync()) return null;
      final dir = p.dirname(oldPath);
      final ext = p.extension(oldPath);
      // Remove caracteres invalidos em nomes do Windows.
      final safe =
          rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
      if (safe.isEmpty) return null;
      var target = p.join(dir, '$safe$ext');
      var n = 2;
      while (target.toLowerCase() != oldPath.toLowerCase() &&
          File(target).existsSync()) {
        target = p.join(dir, '$safe ($n)$ext');
        n++;
      }
      if (target == oldPath) return oldPath;
      await f.rename(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  void _replacePath(int id, String oldPath, String newPath) {
    final list = [...stacks.value];
    final idx = list.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final cur = list[idx];
    final paths = cur.paths.map((x) => x == oldPath ? newPath : x).toList();
    final outputs = cur.outputs.contains(oldPath)
        ? ({...cur.outputs}..remove(oldPath)..add(newPath))
        : cur.outputs;
    list[idx] = FileStack(id, paths, outputs: outputs, name: cur.name);
    stacks.value = list;
  }
}
