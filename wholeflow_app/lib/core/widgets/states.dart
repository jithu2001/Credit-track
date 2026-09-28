import 'package:flutter/material.dart';

import '../errors/app_failure.dart';
import '../theme/app_theme.dart';

/// Placeholder rows shown while a list loads (skeletons, not spinners).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 8, this.padding = EdgeInsets.zero});

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, i) => const SkeletonTile(),
    );
  }
}

class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: Insets.l, vertical: Insets.m),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180, height: 16),
                  SizedBox(height: Insets.s),
                  SkeletonBox(width: 100, height: 12),
                ],
              ),
            ),
            SkeletonBox(width: 90, height: 16),
          ],
        ),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(Insets.xs)),
    );
  }
}

/// Full-area message with an icon, e.g. "No shops match".
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.colors.onSurfaceVariant),
            const SizedBox(height: Insets.l),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Insets.s),
              Text(
                message!,
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: Insets.l), action!],
          ],
        ),
      ),
    );
  }
}

/// Error with friendly copy and a Retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    return EmptyState(
      icon: failure.kind == FailureKind.network ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: failure.kind == FailureKind.network ? "You're offline" : "Couldn't load this",
      message: failure.message,
      action: FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
    );
  }
}

/// A one-row error with Retry, for a section inside a screen.
class ErrorTile extends StatelessWidget {
  const ErrorTile({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.error_outline_rounded),
      title: Text(AppFailure.from(error).message),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}

/// Centers content and caps its width on tablets.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
        child: child,
      ),
    );
  }
}

/// Drops keyboard focus before a sheet, dialog or page opens. Otherwise the
/// field is re-focused when it closes and the keyboard pops up again.
void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
