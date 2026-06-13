import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'fichario.dart';
import 'file_icons.dart';
import 'stacks.dart';

/// Fichário: histórico de pilhas arquivadas. Favoritas no topo;
/// restaurar recria a pilha provisória.
class FicharioView extends StatefulWidget {
  const FicharioView({super.key});

  @override
  State<FicharioView> createState() => _FicharioViewState();
}

class _FicharioViewState extends State<FicharioView> {
  String? _expanded;

  @override
  void initState() {
    super.initState();
    FicharioStore.i.ensureLoaded();
    FicharioStore.i.archived.addListener(_onChange);
    FicharioStore.i.naming.addListener(_onChange);
  }

  @override
  void dispose() {
    FicharioStore.i.archived.removeListener(_onChange);
    FicharioStore.i.naming.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = FicharioStore.i.archived.value;
    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('Arquive uma pilha para vê-la aqui',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    final favs = all.where((e) => e.favorite).toList();
    final rest = favs.isEmpty ? all : all.where((e) => !e.favorite).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      children: [
        if (favs.isNotEmpty) ...[
          _sectionHeader('Favoritas', scheme),
          for (final e in favs) _card(e, scheme),
          _sectionHeader('Todas', scheme),
        ],
        for (final e in rest) _card(e, scheme),
      ],
    );
  }

  Widget _sectionHeader(String t, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(left: 6, top: 8, bottom: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
      );

  Widget _card(ArchivedStack e, ColorScheme scheme) {
    final open = _expanded == e.id;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = open ? null : e.id),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  _deck(e, 24, scheme),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (FicharioStore.i.naming.value.contains(e.id))
                          Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 12, color: scheme.primary),
                              const SizedBox(width: 5),
                              Text('Gerando título…',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          )
                        else
                          Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text('${e.paths.length} docs',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(e.favorite ? Icons.star : Icons.star_border,
                        color: e.favorite ? Colors.amber : null),
                    onPressed: () => FicharioStore.i.toggleFavorite(e.id),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (open) _detail(e, scheme),
        ],
      ),
    );
  }

  Widget _detail(ArchivedStack e, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final path in e.paths.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Icon(iconForName(p.basename(path)),
                      size: 16, color: colorForName(p.basename(path), scheme)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              _action(Icons.unarchive_outlined, 'Restaurar', () {
                StacksController.i.createWith(e.paths);
              }, scheme),
              const SizedBox(width: 8),
              _action(Icons.open_in_new, 'Abrir', () {
                for (final path in e.paths) {
                  launchUrl(Uri.file(path));
                }
              }, scheme),
              const SizedBox(width: 8),
              _action(Icons.delete_outline, 'Apagar', () {
                FicharioStore.i.delete(e.id);
              }, scheme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deck(ArchivedStack e, double size, ColorScheme scheme) {
    final paths = e.paths.take(3).toList();
    final n = paths.length;
    return SizedBox(
      width: size + (n - 1) * size * 0.3,
      height: size,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: i * size * 0.3,
              child: Transform.rotate(
                angle: (i - (n - 1) / 2) * 0.14,
                child: Icon(iconForName(p.basename(paths[i])),
                    size: size,
                    color: colorForName(p.basename(paths[i]), scheme)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(
      IconData icon, String label, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
