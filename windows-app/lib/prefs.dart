import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'hot_corner.dart';

String defaultDownloads() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOMEPATH'] ??
      '';
  return p.join(home, 'Downloads');
}

/// Preferências persistentes (shared_preferences), expostas como
/// ValueNotifiers para a interface e os serviços reagirem ao vivo.
class Prefs {
  Prefs._();
  static final Prefs i = Prefs._();

  late SharedPreferences _sp;

  final folder = ValueNotifier<String>('');
  final corner = ValueNotifier<HotCorner>(HotCorner.bottomRight);
  final accent = ValueNotifier<Color>(const Color(0xFF2E7DF6));

  /// 'timeline' | 'grid' | 'list' — padrão linha do tempo (como no Mac).
  final viewMode = ValueNotifier<String>('timeline');

  /// Incluir capturas do clipboard na linha do tempo.
  final clipboardEnabled = ValueNotifier<bool>(false);

  /// Chave da API do Claude (opcional, para títulos por IA).
  final claudeKey = ValueNotifier<String>('');

  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
    final f = _sp.getString('folder');
    folder.value = (f != null && f.isNotEmpty) ? f : defaultDownloads();
    final c = _sp.getInt('corner');
    corner.value = (c != null && c >= 0 && c < HotCorner.values.length)
        ? HotCorner.values[c]
        : HotCorner.bottomRight;
    final a = _sp.getInt('accent');
    accent.value = a != null ? Color(a) : const Color(0xFF2E7DF6);
    final v = _sp.getString('viewMode');
    viewMode.value = (v == 'grid' || v == 'list' || v == 'timeline')
        ? v!
        : 'timeline';
    clipboardEnabled.value = _sp.getBool('clipboardEnabled') ?? false;
    claudeKey.value = _sp.getString('claudeKey') ?? '';
  }

  void setClaudeKey(String value) {
    claudeKey.value = value;
    _sp.setString('claudeKey', value);
  }

  void setViewMode(String value) {
    viewMode.value = value;
    _sp.setString('viewMode', value);
  }

  void setClipboardEnabled(bool value) {
    clipboardEnabled.value = value;
    _sp.setBool('clipboardEnabled', value);
  }

  void setFolder(String value) {
    folder.value = value;
    _sp.setString('folder', value);
  }

  void setCorner(HotCorner value) {
    corner.value = value;
    _sp.setInt('corner', value.index);
  }

  void setAccent(Color value) {
    accent.value = value;
    // ignore: deprecated_member_use
    _sp.setInt('accent', value.value);
  }
}
