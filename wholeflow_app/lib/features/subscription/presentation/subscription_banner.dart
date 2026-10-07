import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connection/business_connection.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/session_controller.dart';
import '../domain/service_status.dart';
import 'paused_screen.dart';
import 'subscription_providers.dart';

/// The banner text for [status] today, or null when there is nothing to say.
/// Owners see "renewal due" and "grace"; staff only "grace".
@visibleForTesting
({String text, bool urgent})? bannerFor(ServiceStatus? status, {required bool forOwner, DateTime? today}) {
  if (status == null) return null;
  final state = status.stateOn(today ?? businessToday());
  final paid = status.paidUntil == null ? null : formatDate(status.paidUntil!);
  final stops = status.graceUntil == null ? null : formatDate(status.graceUntil!);
  final how = [?status.message, ?status.contact].join(' ');
  switch (state) {
    case AccessState.renewalDue when forOwner:
      return (text: ['Your WholeFlow subscription ends on $paid.', if (how.isNotEmpty) how].join(' '), urgent: false);
    case AccessState.grace when forOwner:
      return (
        text: ['WholeFlow subscription ended on $paid. The app stops on $stops.', if (how.isNotEmpty) how].join(' '),
        urgent: true,
      );
    case AccessState.grace:
      return (text: 'WholeFlow subscription has ended. Ask your owner to renew it before $stops.', urgent: true);
    default:
      return null;
  }
}

/// Wraps every screen of a signed-in app with the subscription banner when
/// one applies (used as `MaterialApp.router(builder: …)`).
class SubscriptionFrame extends ConsumerWidget {
  const SubscriptionFrame({super.key, required this.forOwner, required this.child});

  final bool forOwner;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionControllerProvider).value is SignedIn;
    final banner = signedIn ? bannerFor(ref.watch(serviceStatusProvider).value, forOwner: forOwner) : null;
    if (banner == null) return child;
    final colors = context.colors;
    final bg = banner.urgent ? colors.errorContainer : colors.tertiaryContainer;
    final fg = banner.urgent ? colors.onErrorContainer : colors.onTertiaryContainer;
    return Column(
      children: [
        Material(
          key: const Key('subscription-banner'),
          color: bg,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.l, Insets.s, Insets.l, Insets.s),
              child: Row(
                children: [
                  Icon(banner.urgent ? Icons.error_outline_rounded : Icons.event_rounded, color: fg, size: 20),
                  const SizedBox(width: Insets.m),
                  Expanded(
                    child: Text(banner.text, style: context.text.bodySmall?.copyWith(color: fg)),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}

/// Settings rows: the subscription (owners) and "Switch business".
class SubscriptionSettingsTiles extends ConsumerWidget {
  const SubscriptionSettingsTiles({super.key, required this.forOwner});

  final bool forOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(businessConnectionProvider);
    final status = forOwner ? ref.watch(serviceStatusProvider).value : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status != null && status.paidUntil != null)
          ListTile(
            key: const Key('settings-subscription'),
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(['Subscription', ?status.planName].join(' · ')),
            subtitle: Text(switch (status.stateOn(businessToday())) {
              AccessState.grace =>
                'Ended on ${formatDate(status.paidUntil!)} · stops on ${formatDate(status.graceUntil ?? status.paidUntil!)}',
              _ => 'Paid until ${formatDate(status.paidUntil!)}',
            }),
          ),
        ListTile(
          key: const Key('settings-switch-business'),
          leading: const Icon(Icons.swap_horiz_rounded),
          title: const Text('Switch business'),
          subtitle: Text(
            connection.businessName.isEmpty ? 'Connect with another reference key' : 'Connected to ${connection.businessName}',
          ),
          onTap: () => confirmSwitchBusiness(context, ref),
        ),
      ],
    );
  }
}
