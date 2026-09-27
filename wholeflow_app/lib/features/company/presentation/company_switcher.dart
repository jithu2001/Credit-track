import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/states.dart';
import '../domain/company.dart';
import 'company_providers.dart';

/// App bar title showing the active company; opens a picker when the user
/// can see more than one company.
class CompanyTitle extends ConsumerWidget {
  const CompanyTitle({super.key, required this.screen});

  final String screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies = ref.watch(companiesProvider).value ?? const <Company>[];
    final active = ref.watch(activeCompanyProvider).value;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(screen, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (active != null)
          Text(
            active.companyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
      ],
    );
    if (companies.length < 2) return title;
    return Semantics(
      button: true,
      label: 'Change company, current ${active?.companyName ?? ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(Insets.s),
        onTap: () => showCompanyPicker(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: title),
              const SizedBox(width: Insets.xs),
              const Icon(Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showCompanyPicker(BuildContext context, WidgetRef ref) {
  dismissKeyboard();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final companies = ref.watch(companiesProvider).value ?? const <Company>[];
        final active = ref.watch(activeCompanyProvider).value;
        return ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.s),
              child: Text('Choose company', style: context.text.titleMedium),
            ),
            RadioGroup<String>(
              groupValue: active?.id,
              onChanged: (id) {
                if (id != null) ref.read(selectedCompanyIdProvider.notifier).select(id);
                Navigator.of(context).pop();
              },
              child: Column(
                children: [for (final c in companies) RadioListTile<String>(value: c.id, title: Text(c.companyName))],
              ),
            ),
            const SizedBox(height: Insets.l),
          ],
        );
      },
    ),
  );
}
