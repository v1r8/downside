import 'package:auto_updater/auto_updater.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'clipboard.dart';
import 'prefs.dart';

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
            builder: (_, accent, __) => Wrap(
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
              ],
            ),
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
          _sectionTitle('IA (títulos das pilhas)'),
          Text(
            'Os títulos do fichário são gerados localmente pelo Ollama '
            '(grátis) ou, se preferir, pela API do Claude. Sem nenhum dos '
            'dois, fica o título por data.',
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
          const SizedBox(height: 16),
          _sectionTitle('Atualizações'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Verificar atualizações'),
            subtitle: Text('versão $_version'),
            trailing: FilledButton.tonal(
              onPressed: () => autoUpdater.checkForUpdates(),
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
}
