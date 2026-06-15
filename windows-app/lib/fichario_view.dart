import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'fichario.dart';
import 'file_card.dart';
import 'file_icons.dart';
import 'magic_name.dart';
import 'stacks.dart';

/// Fichário: histórico de pilhas arquivadas. Favoritas no topo (com
/// recolher), busca, multisseleção+apagar, renomear (manual + IA) e
/// restaurar como pilha provisória.
class FicharioView extends StatefulWidget {
  const FicharioView({super.key, this.query = ''});

  final String query;

  @override
  State<FicharioView> createState() => _FicharioViewState();
}

class _FicharioViewState extends State<FicharioView> {
  String? _expanded;
  final Set<String> _selection = {};
  bool _favCollapsed = false;

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
    if (mounted) {
      _selection.removeWhere(
          (id) => !FicharioStore.i.archived.value.any((e) => e.id == id));
      setState(() {});
    }
  }

  String _fold(String s) => s.toLowerCase().trim();

  bool _matches(ArchivedStack e, String q) {
    if (q.isEmpty) return true;
    if (_fold(e.title).contains(q)) return true;
    return e.paths.any((path) => _fold(p.basename(path)).contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _fold(widget.query);
    final all =
        FicharioStore.i.archived.value.where((e) => _matches(e, q)).toList();
    if (all.isEmpty) {
      final empty = FicharioStore.i.archived.value.isEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(empty ? Icons.menu_book_outlined : Icons.search_off,
                size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
                empty
                    ? 'Arquive uma pilha para vê-la aqui'
                    : 'Nada encontrado para a busca',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    final favs = all.where((e) => e.favorite).toList();
    final rest = all.where((e) => !e.favorite).toList();
    return Column(
      children: [
        if (_selection.isNotEmpty) _selectionBar(scheme),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            children: [
              if (favs.isNotEmpty) ...[
                _favHeader(favs.length, scheme),
                if (!_favCollapsed) for (final e in favs) _card(e, scheme),
                _sectionHeader('Todas', scheme),
              ],
              for (final e in rest) _card(e, scheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectionBar(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text('${_selection.length} selecionada(s)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              FicharioStore.i.deleteMany(_selection);
              setState(_selection.clear);
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Apagar'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE5534B)),
          ),
          TextButton(
            onPressed: () => setState(_selection.clear),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  Widget _favHeader(int count, ColorScheme scheme) => InkWell(
        onTap: () => setState(() => _favCollapsed = !_favCollapsed),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(left: 6, top: 8, bottom: 4),
          child: Row(
            children: [
              Icon(_favCollapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 2),
              const Icon(Icons.star, size: 13, color: Colors.amber),
              const SizedBox(width: 5),
              Text('Favoritas ($count)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _sectionHeader(String t, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(left: 6, top: 8, bottom: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
      );

  void _onCardTap(ArchivedStack e) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl || _selection.isNotEmpty) {
      setState(() {
        if (!_selection.add(e.id)) _selection.remove(e.id);
      });
      return;
    }
    setState(() => _expanded = _expanded == e.id ? null : e.id);
  }

  Widget _card(ArchivedStack e, ColorScheme scheme) {
    final open = _expanded == e.id;
    final selected = _selection.contains(e.id);
    final naming = FicharioStore.i.naming.value.contains(e.id);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _onCardTap(e),
            onSecondaryTap: () => _renameDialog(e),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  FileCardDeck(paths: e.paths, height: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (naming)
                          const MagicName(width: 120)
                        else
                          Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text('${e.paths.length} docs · ${_date(e.date)}',
                            style: TextStyle(
                                fontSize: 10.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Favoritar',
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
    final naming = FicharioStore.i.naming.value.contains(e.id);
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
                    child: GestureDetector(
                      onTap: () => launchUrl(Uri.file(path)),
                      child: Text(p.basename(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _action(Icons.unarchive_outlined, 'Restaurar',
                  () => StacksController.i.createWith(e.paths), scheme),
              _action(Icons.open_in_new, 'Abrir', () {
                for (final path in e.paths) {
                  launchUrl(Uri.file(path));
                }
              }, scheme),
              _action(Icons.edit_outlined, 'Renomear', () => _renameDialog(e),
                  scheme),
              _action(Icons.auto_awesome, 'Título IA',
                  naming ? null : () => FicharioStore.i.regenerateTitle(e.id),
                  scheme),
              _action(Icons.delete_outline, 'Apagar',
                  () => FicharioStore.i.delete(e.id), scheme),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _renameDialog(ArchivedStack e) async {
    final ctrl = TextEditingController(text: e.title);
    final novo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear pilha'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (novo != null && novo.trim().isNotEmpty) {
      FicharioStore.i.rename(e.id, novo.trim());
    }
  }

  String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap,
      ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
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
      ),
    );
  }
}
