import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/balance_text.dart';
import '../../../core/widgets/multi_picker_sheet.dart';
import '../../../core/widgets/states.dart';
import '../../company/domain/company.dart';
import '../../company/presentation/company_providers.dart';
import '../data/site_repository.dart';
import '../domain/site.dart';
import 'site_detail_screen.dart';
import 'site_providers.dart';

enum _Show {
  all('All'),
  chosen('In this site'),
  free('In no site');

  const _Show(this.label);
  final String label;
}

/// New site (siteId == null): a name and its shops. Existing site: its shops.
/// A shop is in at most one site, so choosing a shop of another site moves it.
class SiteEditorScreen extends ConsumerWidget {
  const SiteEditorScreen({super.key, this.siteId});

  final String? siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(activeCompanyProvider).value;
    final title = Text(siteId == null ? 'New site' : 'Choose shops');
    if (company == null) return Scaffold(appBar: AppBar(title: title));
    final shops = ref.watch(companySiteShopsProvider(company.id));
    final sites = ref.watch(companySitesProvider(company.id));
    return switch ((shops, sites)) {
      (AsyncValue(value: final sh?), AsyncValue(value: final st?)) =>
        siteId != null && !st.any((s) => s.id == siteId)
            ? Scaffold(
                appBar: AppBar(title: title),
                body: const EmptyState(icon: Icons.location_off_outlined, title: 'This site no longer exists'),
              )
            : _Editor(company: company, siteId: siteId, shops: sh, sites: st),
      (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) => Scaffold(
        appBar: AppBar(title: title),
        body: ErrorState(
          error: error,
          onRetry: () => ref
            ..invalidate(companySiteShopsProvider(company.id))
            ..invalidate(companySitesProvider(company.id)),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: title),
        body: const SkeletonList(),
      ),
    };
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.company, required this.siteId, required this.shops, required this.sites});

  final Company company;
  final String? siteId;
  final List<SiteShop> shops;
  final List<Site> sites;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _name = TextEditingController(text: _site?.name ?? '');
  late final Set<String> _chosen = {
    for (final s in widget.shops)
      if (s.siteId != null && s.siteId == widget.siteId) s.id,
  };
  final _formKey = GlobalKey<FormState>();
  String _query = '';
  _Show _show = _Show.all;
  bool _saving = false;

  bool get _isNew => widget.siteId == null;
  Site? get _site => widget.sites.where((s) => s.id == widget.siteId).firstOrNull;
  late final Map<String, String> _siteNames = {for (final s in widget.sites) s.id: s.name};

  /// Chosen shops that are in another site now (they will move).
  int get _moving => widget.shops.where((s) => _chosen.contains(s.id) && s.siteId != null && s.siteId != widget.siteId).length;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<SiteShop> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final s in widget.shops)
        if ((q.isEmpty || s.name.toLowerCase().contains(q) || (s.area ?? '').toLowerCase().contains(q)) &&
            switch (_show) {
              _Show.all => true,
              _Show.chosen => _chosen.contains(s.id),
              _Show.free => s.siteId == null,
            })
          s,
    ];
  }

  Future<void> _addByArea() async {
    final picked = await showMultiPicker(
      context,
      (context) => Consumer(
        builder: (context, ref, _) {
          final areas = ref.watch(companyAreasProvider(widget.company.id));
          return MultiPickerSheet(
            title: 'Add shops by Tally area',
            searchHint: 'Search areas',
            initial: const {},
            options: areas.value == null ? null : [for (final a in areas.value!) (id: a, label: a)],
            error: areas.error,
            onRetry: () => ref.invalidate(companyAreasProvider(widget.company.id)),
            emptyIcon: Icons.place_outlined,
            emptyTitle: 'No areas found',
            applyLabel: (n) => n == 0 ? 'Add' : 'Add shops of $n area${n == 1 ? '' : 's'}',
          );
        },
      ),
    );
    if (picked == null || picked.isEmpty) return;
    final add = [
      for (final s in widget.shops)
        if (s.area != null && picked.contains(s.area) && !_chosen.contains(s.id)) s.id,
    ];
    setState(() => _chosen.addAll(add));
    if (mounted) showMessage(context, add.isEmpty ? 'Those shops are already chosen' : 'Added ${plural(add.length, 'shop')}');
  }

  Future<void> _save() async {
    if (_isNew && !_formKey.currentState!.validate()) return;
    dismissKeyboard();
    if (_moving > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Move ${plural(_moving, 'shop')}?'),
          content: Text(
            '${plural(_moving, 'shop')} you chose ${_moving == 1 ? 'is' : 'are'} in another site now. '
            'A shop can be in only one site, so ${_moving == 1 ? 'it' : 'they'} will move here.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Move and save')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _saving = true);
    final repo = ref.read(siteRepositoryProvider);
    try {
      if (_isNew) {
        final id = await repo.create(widget.company.id, _name.text, _chosen);
        invalidateSiteData(ref);
        if (!mounted) return;
        showMessage(context, '${_name.text.trim()} created');
        context.pushReplacement('/sites/$id');
      } else {
        await repo.setShops(widget.siteId!, _chosen);
        invalidateSiteData(ref);
        if (!mounted) return;
        showMessage(context, 'Shops saved');
        context.pop();
      }
    } on AppFailure catch (f) {
      if (mounted) showMessage(context, f.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New site' : _site!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(onPressed: _addByArea, icon: const Icon(Icons.playlist_add_rounded), label: const Text('By area')),
        ],
      ),
      body: ContentWidth(
        child: Column(
          children: [
            if (_isNew)
              Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
                  child: TextFormField(
                    key: const Key('site-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Site name', hintText: 'e.g. Thodupuzha town'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, 0),
              child: SearchBar(
                hintText: 'Search shops or areas',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.s),
                children: [
                  for (final v in _Show.values) ...[
                    ChoiceChip(label: Text(v.label), selected: _show == v, onSelected: (_) => setState(() => _show = v)),
                    const SizedBox(width: Insets.s),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? const EmptyState(icon: Icons.search_off_rounded, title: 'No shops here')
                  : ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final s = visible[i];
                        final other = s.siteId != null && s.siteId != widget.siteId ? _siteNames[s.siteId] : null;
                        return CheckboxListTile(
                          value: _chosen.contains(s.id),
                          onChanged: (on) => setState(() => on == true ? _chosen.add(s.id) : _chosen.remove(s.id)),
                          title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                if (s.area != null) TextSpan(text: s.area),
                                if (s.area != null && other != null) const TextSpan(text: ' · '),
                                if (other != null)
                                  TextSpan(
                                    text: 'in $other',
                                    style: TextStyle(color: context.semantic.warning, fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),
                            style: muted,
                          ),
                          secondary: SizedBox(
                            width: 96,
                            child: BalanceText(s.receivable, textAlign: TextAlign.end, compact: true),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
          child: FilledButton(
            key: const Key('save-site'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _isNew
                        ? 'Create site with ${plural(_chosen.length, 'shop')}'
                        : 'Save ${plural(_chosen.length, 'shop')}${_moving > 0 ? ' ($_moving moving here)' : ''}',
                  ),
          ),
        ),
      ),
    );
  }
}
