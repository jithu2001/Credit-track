import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'states.dart';

/// One choice in a [MultiPickerSheet].
typedef PickerOption = ({String id, String label});

/// Searchable multi-select in a bottom sheet; pops the chosen ids.
/// [options] is loading while null; [error] shows with [onRetry].
class MultiPickerSheet extends StatefulWidget {
  const MultiPickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.initial,
    required this.onRetry,
    this.error,
    this.searchHint = 'Search',
    this.emptyTitle = 'Nothing to choose from',
    this.emptyIcon = Icons.search_off_rounded,
    this.applyLabel,
  });

  final String title;
  final List<PickerOption>? options;
  final Set<String> initial;
  final Object? error;
  final VoidCallback onRetry;
  final String searchHint;
  final String emptyTitle;
  final IconData emptyIcon;

  /// Button text for the chosen count; defaults to "Apply (n)" / "Apply".
  final String Function(int count)? applyLabel;

  @override
  State<MultiPickerSheet> createState() => _MultiPickerSheetState();
}

class _MultiPickerSheetState extends State<MultiPickerSheet> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final options = widget.options;
    // Keep the list above the keyboard while searching.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.s, 0),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: context.text.titleMedium)),
                  TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.xs, Insets.l, Insets.s),
              child: TextField(
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: widget.error != null
                  ? ErrorState(error: widget.error!, onRetry: widget.onRetry)
                  : options == null
                  ? const SkeletonList()
                  : options.isEmpty
                  ? EmptyState(icon: widget.emptyIcon, title: widget.emptyTitle)
                  : ListView(
                      controller: scroll,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        for (final o in options)
                          if (q.isEmpty || o.label.toLowerCase().contains(q) || _selected.contains(o.id))
                            CheckboxListTile(
                              value: _selected.contains(o.id),
                              title: Text(o.label),
                              onChanged: (on) => setState(() => on == true ? _selected.add(o.id) : _selected.remove(o.id)),
                            ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Insets.l),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(
                      widget.applyLabel?.call(_selected.length) ?? (_selected.isEmpty ? 'Apply' : 'Apply (${_selected.length})'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [builder] (a [MultiPickerSheet], usually inside a Consumer so its
/// options can load) and returns the chosen ids, or null if dismissed.
Future<Set<String>?> showMultiPicker(BuildContext context, WidgetBuilder builder) {
  dismissKeyboard();
  return showModalBottomSheet<Set<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: builder,
  );
}
