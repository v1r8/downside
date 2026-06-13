import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'downloads_view.dart';
import 'hot_corner.dart';

/// Feed de atualização do Windows (tag fixa "windows", URL estável).
const String kFeedURL =
    'https://github.com/v1r8/downside/releases/download/windows/appcast-win.xml';
const String kTrayIcon = 'assets/tray.ico';

final PanelController panel = PanelController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(560, 420),
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    // Começa escondido: abre pelo canto da tela ou pela bandeja.
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

/// Controla a janela em modo painel: posiciona no canto, mostra/esconde,
/// com período de carência para o "fechar ao clicar fora".
class PanelController {
  bool visible = false;
  bool pinned = false;
  DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> showAt(HotCorner corner) async {
    await windowManager.setAlignment(_alignmentFor(corner));
    await windowManager.show();
    await windowManager.focus();
    visible = true;
    _shownAt = DateTime.now();
  }

  Future<void> hide() async {
    if (!visible) return;
    visible = false;
    await windowManager.hide();
  }

  /// Clique fora (perda de foco) fecha — respeitando o pin e uma
  /// carência de 400 ms após abrir (evita fechar no próprio show).
  void handleBlur() {
    if (!visible || pinned) return;
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
    return MaterialApp(
      title: 'Downside',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7DF6),
          brightness: Brightness.dark,
        ),
      ),
      home: const PanelScaffold(),
    );
  }
}

class PanelScaffold extends StatefulWidget {
  const PanelScaffold({super.key});

  @override
  State<PanelScaffold> createState() => _PanelScaffoldState();
}

class _PanelScaffoldState extends State<PanelScaffold>
    with TrayListener, WindowListener {
  late final HotCornerService _hotCorner;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    _hotCorner = HotCornerService(onTrigger: (corner) => panel.showAt(corner));
    _hotCorner.start();
  }

  @override
  void dispose() {
    _hotCorner.stop();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _focusNode.dispose();
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
            MenuItem(key: 'check_updates', label: 'Verificar atualizações'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Sair'),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  void onWindowBlur() => panel.handleBlur();

  @override
  void onTrayIconMouseDown() => panel.showAt(HotCorner.bottomRight);

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        panel.showAt(HotCorner.bottomRight);
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
      body: Focus(
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
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              _header(scheme),
              const Divider(height: 1),
              const Expanded(child: DownloadsView()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return DragToMoveArea(
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.download_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('Downloads',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              tooltip: panel.pinned ? 'Liberar' : 'Fixar',
              iconSize: 16,
              onPressed: () => setState(() => panel.pinned = !panel.pinned),
              icon: Icon(panel.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            ),
            IconButton(
              tooltip: 'Fechar',
              iconSize: 16,
              onPressed: () => panel.hide(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
