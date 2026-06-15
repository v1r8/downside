import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ai.dart';
import 'clipboard.dart';
import 'main.dart' show panel;
import 'prefs.dart';
import 'smart_names.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '…';

  static const List<Color> _swatches = [
    Color(0xFF2E7DF6), // azul
    Color(0xFF34C4C4), // teal
    Color(0xFF8B5CF6), // roxo
    Color(0xFFEC4899), // rosa
    Color(0xFFF59E0B), // âmbar
    Color(0xFF22C55E), // verde
  ];

  static const Map<String, String> _triggerLabels = {
    'topLeft': 'Canto superior esquerdo',
    'topRight': 'Canto superior direito',
    'bottomLeft': 'Canto inferior esquerdo',
    'bottomRight': 'Canto inferior direito',
    'left': 'Lateral esquerda',
    'right': 'Lateral direita',
  };

  static const Map<String, String> _clipMarkLabels = {
    'badge': 'Selo de clipboard',
    'bar': 'Barra lateral colorida',
    'tint': 'Fundo levemente tingido',
  };

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Configurações'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _sectionTitle('Pasta monitorada'),
          ValueListenableBuilder<String>(
            valueListenable: Prefs.i.folder,
            builder: (_, folder, __) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(folder, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: FilledButton.tonal(
                onPressed: _pickFolder,
                child: const Text('Alterar…'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Abertura (cantos e laterais)'),
          ValueListenableBuilder<Set<String>>(
            valueListenable: Prefs.i.triggers,
            builder: (_, triggers, __) => Column(
              children: [
                for (final entry in _triggerLabels.entries)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.value),
                    value: triggers.contains(entry.key),
                    onChanged: (_) => Prefs.i.toggleTrigger(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Cor de destaque'),
          ValueListenableBuilder<Color>(
            valueListenable: Prefs.i.accent,
            builder: (_, accent, __) {
              final isCustom = !_swatches
                  .any((c) => c.toARGB32() == accent.toARGB32());
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _swatches)
                    GestureDetector(
                      onTap: () => Prefs.i.setAccent(c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.toARGB32() == c.toARGB32()
                                ? Colors.white
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  // Cor personalizada (qualquer cor).
                  GestureDetector(
                    onTap: () => _pickCustomColor(accent),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: const SweepGradient(colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ]),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCustom ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: const Icon(Icons.colorize,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _sectionTitle('Exibição'),
          ValueListenableBuilder<String>(
            valueListenable: Prefs.i.viewMode,
            builder: (_, mode, __) => Column(
              children: [
                for (final entry in const {
                  'timeline': 'Linha do tempo',
                  'grid': 'Grade',
                  'list': 'Lista',
                }.entries)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: mode,
                    onChanged: (v) => Prefs.i.setViewMode(v!),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: Prefs.i.cardLightBackground,
            builder: (_, on, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Cartas com fundo claro'),
              subtitle: const Text(
                  'Ícones dos arquivos sobre fundo branco — mais clean.'),
              value: on,
              onChanged: Prefs.i.setCardLightBackground,
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Preview ao pairar'),
          ValueListenableBuilder<bool>(
            valueListenable: Prefs.i.hoverEnabled,
            builder: (_, on, __) => Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Mostrar preview ao pairar o mouse'),
                  value: on,
                  onChanged: Prefs.i.setHoverEnabled,
                ),
                if (on)
                  ValueListenableBuilder<int>(
                    valueListenable: Prefs.i.hoverDelay,
                    builder: (_, ms, __) => Row(
                      children: [
                        const Text('Atraso', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            min: 200,
                            max: 2000,
                            divisions: 18,
                            value: ms.toDouble(),
                            label: '${(ms / 1000).toStringAsFixed(1)} s',
                            onChanged: (v) =>
                                Prefs.i.setHoverDelay(v.round()),
                          ),
                        ),
                        Text('${(ms / 1000).toStringAsFixed(1)} s',
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Clipboard'),
          ValueListenableBuilder<bool>(
            valueListenable: Prefs.i.clipboardEnabled,
            builder: (_, on, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Incluir clipboard na linha do tempo'),
              subtitle: const Text(
                  'Textos e imagens copiados aparecem junto com os arquivos.'),
              value: on,
              onChanged: (v) {
                Prefs.i.setClipboardEnabled(v);
                if (v) {
                  ClipboardMonitor.i.start();
                } else {
                  ClipboardMonitor.i.stop();
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text('Como destacar os itens do clipboard:',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          ValueListenableBuilder<String>(
            valueListenable: Prefs.i.clipboardMark,
            builder: (_, mark, __) => Wrap(
              spacing: 8,
              children: [
                for (final entry in _clipMarkLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                    selected: mark == entry.key,
                    onSelected: (_) => Prefs.i.setClipboardMark(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Segurança do clipboard'),
          ValueListenableBuilder<bool>(
            valueListenable: Prefs.i.clipboardSkipSecretLike,
            builder: (_, on, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Ignorar textos com cara de segredo'),
              subtitle: const Text(
                  'Chaves de API, tokens e senhas não são capturados.'),
              value: on,
              onChanged: Prefs.i.setClipboardSkipSecretLike,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text('Guardar o histórico por:',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Prefs.i.clipboardRetentionHours,
            builder: (_, hours, __) => Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  1: '1 hora',
                  24: '1 dia',
                  168: '1 semana',
                  720: '30 dias',
                  0: 'Sempre',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                    selected: hours == entry.key,
                    onSelected: (_) =>
                        Prefs.i.setClipboardRetentionHours(entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () {
                ClipboardMonitor.i.clearAll();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Histórico do clipboard limpo')),
                );
              },
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Limpar histórico do clipboard'),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Nomes inteligentes'),
          ValueListenableBuilder<bool>(
            valueListenable: Prefs.i.smartNames,
            builder: (_, on, __) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Nomear arquivos com IA local'),
              subtitle: const Text(
                  'Apelidos legíveis (Ollama/Claude) — só visual; o arquivo '
                  'no disco não muda. O tipo vira uma etiqueta ao lado.'),
              value: on,
              onChanged: Prefs.i.setSmartNames,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                SmartNameStore.i.reset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nomes gerados esquecidos')),
                );
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Esquecer nomes gerados'),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('IA local (Ollama)'),
          Text(
            'A IA local roda no seu computador (grátis e privada) e cuida de '
            'nomear pilhas, renomear documentos e os títulos do fichário. '
            'Precisa do Ollama instalado e de um modelo baixado.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          const _OllamaSection(),
          const SizedBox(height: 12),
          _sectionTitle('IA na nuvem (Claude — opcional)'),
          Text(
            'Se não quiser usar a IA local, uma chave do Claude faz o mesmo '
            'trabalho pela internet. Sem Ollama nem chave, ficam os nomes por '
            'data.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: Prefs.i.claudeKey.value),
            obscureText: true,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Chave da API do Claude (opcional)',
              hintText: 'sk-ant-…',
              border: OutlineInputBorder(),
            ),
            onChanged: Prefs.i.setClaudeKey,
          ),
          const SizedBox(height: 8),
          _sectionTitle('Ações em massa (pilhas)'),
          ValueListenableBuilder<int>(
            valueListenable: Prefs.i.bulkAIEngine,
            builder: (_, engine, __) => Column(
              children: [
                for (final entry in const {
                  1: 'Automático (local, depois Claude)',
                  3: 'Somente IA local (Ollama)',
                  2: 'Somente Claude (nuvem)',
                }.entries)
                  RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: engine,
                    onChanged: (v) => Prefs.i.setBulkAIEngine(v!),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text('Profundidade do resumo:',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Prefs.i.summaryDepth,
            builder: (_, depth, __) => Wrap(
              spacing: 8,
              children: [
                for (final entry in const {1: 'Curto', 2: 'Denso'}.entries)
                  ChoiceChip(
                    label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                    selected: depth == entry.key,
                    onSelected: (_) => Prefs.i.setSummaryDepth(entry.key),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Prefs.i.keywordCount,
            builder: (_, count, __) => Row(
              children: [
                const Text('Palavras-chave', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    min: 5,
                    max: 20,
                    divisions: 15,
                    value: count.toDouble(),
                    label: '$count',
                    onChanged: (v) => Prefs.i.setKeywordCount(v.round()),
                  ),
                ),
                Text('$count',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Fechamento'),
          ValueListenableBuilder<bool>(
            valueListenable: Prefs.i.autoHideOnLeave,
            builder: (_, on, __) => Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Fechar quando o mouse se afasta'),
                  value: on,
                  onChanged: Prefs.i.setAutoHideOnLeave,
                ),
                if (on)
                  ValueListenableBuilder<double>(
                    valueListenable: Prefs.i.hideMargin,
                    builder: (_, margin, __) => Row(
                      children: [
                        const Text('Distância', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            min: 50,
                            max: 600,
                            divisions: 22,
                            value: margin,
                            label: '${margin.round()} px',
                            onChanged: (v) => Prefs.i.setHideMargin(v),
                          ),
                        ),
                        Text('${margin.round()} px',
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Atualizações'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Verificar atualizações'),
            subtitle: Text('versão $_version'),
            trailing: FilledButton.tonal(
              onPressed: () => panel.beginUpdateCheck(),
              child: const Text('Verificar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath();
    if (dir != null && dir.isNotEmpty) {
      Prefs.i.setFolder(dir);
    }
  }

  Future<void> _pickCustomColor(Color current) async {
    var picked = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cor personalizada'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Usar'),
          ),
        ],
      ),
    );
    if (ok == true) Prefs.i.setAccent(picked);
  }
}

/// Painel da IA local: status do Ollama, modelos baixados (escolher o
/// ativo), e baixar um novo modelo com barra de progresso.
class _OllamaSection extends StatefulWidget {
  const _OllamaSection();

  @override
  State<_OllamaSection> createState() => _OllamaSectionState();
}

class _OllamaSectionState extends State<_OllamaSection> {
  bool _checking = true;
  bool _running = false;
  List<String> _models = [];

  final _pullCtrl = TextEditingController(text: 'llama3.2:3b');
  bool _pulling = false;
  double _pullProgress = 0;
  String _pullStatus = '';

  // Modelos pequenos e bons para nomear documentos.
  static const _suggested = ['llama3.2:3b', 'qwen2.5:3b', 'gemma2:2b'];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pullCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final running = await OllamaService.isRunning();
    final models = running ? await OllamaService.listModels() : <String>[];
    if (!mounted) return;
    setState(() {
      _checking = false;
      _running = running;
      _models = models;
    });
  }

  Future<void> _pull(String name) async {
    if (_pulling || name.trim().isEmpty) return;
    setState(() {
      _pulling = true;
      _pullProgress = 0;
      _pullStatus = 'Conectando…';
    });
    final ok = await OllamaService.pullModel(
      name.trim(),
      onProgress: (status, prog) {
        if (!mounted) return;
        setState(() {
          _pullStatus = status;
          if (prog > 0) _pullProgress = prog;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _pulling = false;
      _pullStatus = ok ? 'Baixado ✓' : 'Falhou — Ollama está rodando?';
    });
    if (ok) {
      Prefs.i.setOllamaModel(name.trim());
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status
        Row(
          children: [
            if (_checking)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(_running ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: _running ? const Color(0xFF22C55E) : scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _checking
                    ? 'Verificando o Ollama…'
                    : _running
                        ? 'Ollama rodando — ${_models.length} modelo(s) baixado(s)'
                        : 'Ollama não encontrado em 127.0.0.1:11434',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            IconButton(
              tooltip: 'Recarregar',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: _checking ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (!_checking && !_running)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: GestureDetector(
              onTap: () =>
                  launchUrl(Uri.parse('https://ollama.com/download')),
              child: Text(
                'Instalar o Ollama (ollama.com/download) e abri-lo.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.primary,
                    decoration: TextDecoration.underline),
              ),
            ),
          ),

        // Modelos baixados — escolher o ativo
        if (_running) ...[
          const SizedBox(height: 8),
          Text('Modelo usado para nomear:',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          if (_models.isEmpty)
            Text('Nenhum modelo baixado ainda — baixe um abaixo.',
                style:
                    TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant))
          else
            ValueListenableBuilder<String>(
              valueListenable: Prefs.i.ollamaModel,
              builder: (_, active, __) => Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in _models)
                    ChoiceChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: active == m,
                      onSelected: (_) => Prefs.i.setOllamaModel(m),
                    ),
                ],
              ),
            ),
        ],

        // Baixar modelo
        const SizedBox(height: 12),
        Text('Baixar um modelo:',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final s in _suggested)
              ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 11)),
                onPressed: _pulling ? null : () => _pull(s),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pullCtrl,
                enabled: !_pulling,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Nome do modelo (ex.: llama3.2:3b)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _pulling ? null : () => _pull(_pullCtrl.text),
              child: const Text('Baixar'),
            ),
          ],
        ),
        if (_pulling || _pullStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_pulling)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _pullProgress > 0 ? _pullProgress : null,
                      minHeight: 6,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _pulling && _pullProgress > 0
                      ? '$_pullStatus — ${(_pullProgress * 100).round()}%'
                      : _pullStatus,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
