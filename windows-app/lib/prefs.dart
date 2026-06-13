import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Chaves dos gatilhos de abertura (cantos + laterais).
const kTriggerKeys = [
  'topLeft',
  'topRight',
  'bottomLeft',
  'bottomRight',
  'left',
  'right',
];

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

  /// Gatilhos ativos: cantos (topLeft/…/bottomRight) e laterais (left/right).
  final triggers = ValueNotifier<Set<String>>({'bottomRight'});

  /// Estilo da marca dos itens do clipboard: 'badge' | 'bar' | 'tint'.
  final clipboardMark = ValueNotifier<String>('badge');

  final accent = ValueNotifier<Color>(const Color(0xFF2E7DF6));

  /// 'timeline' | 'grid' | 'list' — padrão linha do tempo (como no Mac).
  final viewMode = ValueNotifier<String>('timeline');

  /// Incluir capturas do clipboard na linha do tempo.
  final clipboardEnabled = ValueNotifier<bool>(false);

  /// Chave da API do Claude (opcional, para títulos por IA).
  final claudeKey = ValueNotifier<String>('');

  /// Preview ao pairar (hover).
  final hoverEnabled = ValueNotifier<bool>(true);
  final hoverDelay = ValueNotifier<int>(600); // ms

  /// Nomes inteligentes dos arquivos (apelido por IA local) — só visual.
  final smartNames = ValueNotifier<bool>(false);

  Future<void> load() async {
    _sp = await SharedPreferences.getInstance();
    final f = _sp.getString('folder');
    folder.value = (f != null && f.isNotEmpty) ? f : defaultDownloads();
    final t = _sp.getStringList('triggers');
    triggers.value = (t != null && t.isNotEmpty)
        ? t.where(kTriggerKeys.contains).toSet()
        : {'bottomRight'};
    if (triggers.value.isEmpty) triggers.value = {'bottomRight'};
    clipboardMark.value = _sp.getString('clipboardMark') ?? 'badge';
    final a = _sp.getInt('accent');
    accent.value = a != null ? Color(a) : const Color(0xFF2E7DF6);
    final v = _sp.getString('viewMode');
    viewMode.value = (v == 'grid' || v == 'list' || v == 'timeline')
        ? v!
        : 'timeline';
    clipboardEnabled.value = _sp.getBool('clipboardEnabled') ?? false;
    claudeKey.value = _sp.getString('claudeKey') ?? '';
    hoverEnabled.value = _sp.getBool('hoverEnabled') ?? true;
    hoverDelay.value = _sp.getInt('hoverDelay') ?? 600;
    smartNames.value = _sp.getBool('smartNames') ?? false;
  }

  void setSmartNames(bool v) {
    smartNames.value = v;
    _sp.setBool('smartNames', v);
  }

  void setHoverEnabled(bool v) {
    hoverEnabled.value = v;
    _sp.setBool('hoverEnabled', v);
  }

  void setHoverDelay(int ms) {
    hoverDelay.value = ms;
    _sp.setInt('hoverDelay', ms);
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

  void toggleTrigger(String key) {
    final s = {...triggers.value};
    if (!s.add(key)) s.remove(key);
    if (s.isEmpty) s.add('bottomRight'); // sempre ao menos um
    triggers.value = s;
    _sp.setStringList('triggers', s.toList());
  }

  void setClipboardMark(String value) {
    clipboardMark.value = value;
    _sp.setString('clipboardMark', value);
  }

  void setAccent(Color value) {
    accent.value = value;
    // ignore: deprecated_member_use
    _sp.setInt('accent', value.value);
  }
}
