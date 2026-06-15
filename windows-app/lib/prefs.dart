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

  /// Modelo do Ollama usado para nomear/renomear (ex.: 'llama3.2:3b').
  final ollamaModel = ValueNotifier<String>('llama3.2:3b');

  /// Tamanho do painel (lembrado entre fechar/abrir). Mínimos no setter.
  final panelWidth = ValueNotifier<double>(560);
  final panelHeight = ValueNotifier<double>(430);

  /// Ações em massa (portado do Mac):
  /// profundidade do resumo (1=curto, 2=denso), nº de palavras-chave (5–20),
  /// motor de IA (1=automático local→Claude, 2=só Claude, 3=só local/Ollama).
  final summaryDepth = ValueNotifier<int>(2);
  final keywordCount = ValueNotifier<int>(10);
  final bulkAIEngine = ValueNotifier<int>(1);

  /// Fecha o painel quando o mouse se afasta, e a distância (px) p/ fechar.
  final autoHideOnLeave = ValueNotifier<bool>(true);
  final hideMargin = ValueNotifier<double>(220);

  /// Segurança do clipboard: ignorar textos com cara de segredo (chaves,
  /// tokens, senhas) e por quantas horas guardar o histórico (0 = sempre).
  final clipboardSkipSecretLike = ValueNotifier<bool>(true);
  final clipboardRetentionHours = ValueNotifier<int>(168);

  /// Cartas com fundo claro (branco) — visual mais clean. Senão, escuro.
  final cardLightBackground = ValueNotifier<bool>(true);

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
    final om = _sp.getString('ollamaModel');
    ollamaModel.value = (om != null && om.trim().isNotEmpty) ? om : 'llama3.2:3b';
    panelWidth.value = (_sp.getDouble('panelWidth') ?? 560).clamp(380, 1400).toDouble();
    panelHeight.value = (_sp.getDouble('panelHeight') ?? 430).clamp(300, 1200).toDouble();
    summaryDepth.value = (_sp.getInt('summaryDepth') ?? 2).clamp(1, 2).toInt();
    keywordCount.value = (_sp.getInt('keywordCount') ?? 10).clamp(5, 20).toInt();
    bulkAIEngine.value = (_sp.getInt('bulkAIEngine') ?? 1).clamp(1, 3).toInt();
    autoHideOnLeave.value = _sp.getBool('autoHideOnLeave') ?? true;
    hideMargin.value = (_sp.getDouble('hideMargin') ?? 220).clamp(50, 600).toDouble();
    clipboardSkipSecretLike.value =
        _sp.getBool('clipboardSkipSecretLike') ?? true;
    clipboardRetentionHours.value = _sp.getInt('clipboardRetentionHours') ?? 168;
    cardLightBackground.value = _sp.getBool('cardLightBackground') ?? true;
  }

  void setCardLightBackground(bool v) {
    cardLightBackground.value = v;
    _sp.setBool('cardLightBackground', v);
  }

  void setClipboardSkipSecretLike(bool v) {
    clipboardSkipSecretLike.value = v;
    _sp.setBool('clipboardSkipSecretLike', v);
  }

  void setClipboardRetentionHours(int v) {
    clipboardRetentionHours.value = v;
    _sp.setInt('clipboardRetentionHours', v);
  }

  void setPanelSize(double w, double h) {
    final cw = w.clamp(380.0, 1400.0).toDouble();
    final ch = h.clamp(300.0, 1200.0).toDouble();
    panelWidth.value = cw;
    panelHeight.value = ch;
    _sp.setDouble('panelWidth', cw);
    _sp.setDouble('panelHeight', ch);
  }

  void setSummaryDepth(int v) {
    summaryDepth.value = v.clamp(1, 2).toInt();
    _sp.setInt('summaryDepth', summaryDepth.value);
  }

  void setKeywordCount(int v) {
    keywordCount.value = v.clamp(5, 20).toInt();
    _sp.setInt('keywordCount', keywordCount.value);
  }

  void setBulkAIEngine(int v) {
    bulkAIEngine.value = v.clamp(1, 3).toInt();
    _sp.setInt('bulkAIEngine', bulkAIEngine.value);
  }

  void setAutoHideOnLeave(bool v) {
    autoHideOnLeave.value = v;
    _sp.setBool('autoHideOnLeave', v);
  }

  void setHideMargin(double v) {
    hideMargin.value = v.clamp(50, 600).toDouble();
    _sp.setDouble('hideMargin', hideMargin.value);
  }

  void setSmartNames(bool v) {
    smartNames.value = v;
    _sp.setBool('smartNames', v);
  }

  void setOllamaModel(String v) {
    final m = v.trim().isEmpty ? 'llama3.2:3b' : v.trim();
    ollamaModel.value = m;
    _sp.setString('ollamaModel', m);
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
