import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'downloads_view.dart';
import 'hot_corner.dart';
import 'prefs.dart';
import 'settings_screen.dart';

const String kFeedURL =
    'https://github.com/v1r8/downside/releases/download/windows/appcast-win.xml';
const String kTrayIcon = 'assets/tray.ico';

final PanelController panel = PanelController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Window.initialize();
  await Prefs.i.load();

  const options = WindowOptions(
    size: Size(560, 430),
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    try {
      await Window.setEffect(
        effect: WindowEffect.acrylic,
        color: const Color(0xCC1C1C1E),
        dark: true,
      );
    } catch (_) {}
    await windowManager.hide();
  });

  unawaited(_setupUpdater());
  runApp(const DownsideApp());
}

Future<void> _setupUpdater() async {
  try {
    await autoUpdater.setFeedURL(kFeedURL);
    await autoUpdater.setScheduledCheckInterval(3600);
    await autoUpdater.checkForUpdates();
  } catch (_) {}
}

/// Controla a janela em modo painel.
class PanelController {
  bool visible = false;
  bool pinned = false;
  bool settingsOpen = false;
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Incrementa a cada abertura — dispara a animação de entrada.
  final ValueNotifier<int> showTick = ValueNotifier<int>(0);

  Future<void> showAt(HotCorner corner) async {
    await windowManager.setAlignment(_alignmentFor(corner));
    await windowManager.show();
    await windowManager.focus();
    visible = true;
    _shownAt = DateTime.now();
    showTick.value++;
  }

  Future<void> hide() async {
    if (!visible) return;
    visible = false;
    await windowManager.hide();
  }

  void handleBlur() {
    if (!visible || pinned || settingsOpen) return;
    if (DateTime.now().difference(_shownAt) <
        const Duration(milliseconds: 400)) {
      return;
    }
    hide();
  }

  Alignment _alignmentFor(HotCorner c) {
    switch (c) {
      case HotCorner.topLeft:
        return Alignment.topLeft;
      case HotCorner.topRight:
        return Alignment.topRight;
      case HotCorner.bottomLeft:
        return Alignment.bottomLeft;
      case HotCorner.bottomRight:
        return Alignment.bottomRight;
    }
  }
}

class DownsideApp extends StatelessWidget {
  const DownsideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: Prefs.i.accent,
      builder: (_, accent, __) {
        return MaterialApp(
          title: 'Downside',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
              brightness: Brightness.dark,
            ),
          ),
          // Cantos arredondados do painel em todas as telas.
          builder: (context, child) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: child,
          ),
          home: const PanelScaffold(),
        );
      },
    );
  }
}

class PanelScaffold extends StatefulWidget {
  const PanelScaffold({super.key});

  @override
  State<PanelScaffold> createState() => _PanelScaffoldState();
}

class _PanelScaffoldState extends State<PanelScaffold>
    with TrayListener, WindowListener, SingleTickerProviderStateMixin {
  late final HotCornerService _hotCorner;
  late final AnimationController _anim;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
    panel.showTick.addListener(_onShow);
    _initTray();
    _hotCorner = HotCornerService(
      onTrigger: (corner) => panel.showAt(corner),
      enabledCorner: () => Prefs.i.corner.value,
    );
    _hotCorner.start();
  }

  void _onShow() {
    _searchCtrl.clear();
    setState(() => _query = '');
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    panel.showTick.removeListener(_onShow);
    _hotCorner.stop();
    _anim.dispose();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _focusNode.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon(kTrayIcon);
      await trayManager.setToolTip('Downside');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Mostrar painel'),
            MenuItem(key: 'settings', label: 'Configurações'),
            MenuItem(key: 'check_updates', label: 'Verificar atualizações'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Sair'),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    panel.settingsOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    panel.settingsOpen = false;
  }

  @override
  void onWindowBlur() => panel.handleBlur();

  @override
  void onTrayIconMouseDown() => panel.showAt(Prefs.i.corner.value);

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        panel.showAt(Prefs.i.corner.value);
        break;
      case 'settings':
        panel.showAt(Prefs.i.corner.value);
        _openSettings();
        break;
      case 'check_updates':
        unawaited(autoUpdater.checkForUpdates());
        break;
      case 'quit':
        windowManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeTransition(
        opacity: _anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(
            CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
          ),
          alignment: Alignment.bottomRight,
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                panel.hide();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.55),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _header(scheme),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  Expanded(child: DownloadsView(query: _query)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.download_rounded, size: 20, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: _searchField(scheme)),
          const SizedBox(width: 4),
          _iconButton(
            panel.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            panel.pinned ? 'Liberar' : 'Fixar',
            () => setState(() => panel.pinned = !panel.pinned),
            active: panel.pinned,
          ),
          _iconButton(Icons.settings_outlined, 'Configurações', _openSettings),
        ],
      ),
    );
  }

  Widget _searchField(ColorScheme scheme) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Buscar',
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap,
      {bool active = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      color: active ? scheme.primary : null,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}
