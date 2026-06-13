import 'package:flutter/foundation.dart';

/// Uma pilha temporaria (deck de cartas): conjunto de arquivos reunido
/// por arrasto. Ate 3 ao mesmo tempo. Portado das pilhas do Mac.
class FileStack {
  FileStack(this.id, this.paths, {this.outputs = const {}});
  final int id;
  final List<String> paths;
  final Set<String> outputs;

  bool get hadBulkAction => outputs.isNotEmpty;
}

class StacksController {
  StacksController._();
  static final StacksController i = StacksController._();

  static const int maxStacks = 3;

  final stacks = ValueNotifier<List<FileStack>>([]);
  int _nextId = 1;

  /// Cria uma nova pilha com os arquivos (dedup). Se ja houver 3,
  /// adiciona na ultima.
  void createWith(List<String> paths) {
    final clean = paths.where((p) => p.trim().isNotEmpty).toSet().toList();
    if (clean.isEmpty) return;
    final list = [...stacks.value];
    if (list.length >= maxStacks) {
      final last = list.last;
      final merged = {...last.paths, ...clean}.toList();
      list[list.length - 1] = FileStack(last.id, merged, outputs: last.outputs);
    } else {
      list.add(FileStack(_nextId++, clean));
    }
    stacks.value = list;
  }

  void addTo(int id, List<String> paths) {
    final list = [...stacks.value];
    final idx = list.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final merged = {...list[idx].paths, ...paths}.toList();
    list[idx] = FileStack(id, merged, outputs: list[idx].outputs);
    stacks.value = list;
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
          outputs: {...list[idx].outputs}..remove(path));
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
    list[idx] = FileStack(id, paths, outputs: {...list[idx].outputs, path});
    stacks.value = list;
  }
}
