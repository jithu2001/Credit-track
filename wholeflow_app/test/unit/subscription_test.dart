import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wholeflow_app/core/connection/business_connection.dart';
import 'package:wholeflow_app/core/api/api_client.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/router/owner_router.dart';
import 'package:wholeflow_app/core/router/staff_router.dart';
import 'package:wholeflow_app/features/auth/presentation/session_controller.dart';
import 'package:wholeflow_app/features/subscription/domain/service_status.dart';
import 'package:wholeflow_app/features/subscription/presentation/subscription_banner.dart';

DateTime d(String s) => DateTime.parse('${s}T00:00:00Z');

const status = ServiceStatus(
  status: 'active',
  paidUntil: null,
  planName: 'Standard',
  message: 'Pay ₹800 by UPI.',
  contact: '98470 00000',
);

ServiceStatus paidTo(String paid, {String state = 'active'}) => ServiceStatus.fromJson({
  'status': state,
  'paid_until': paid,
  'grace_until': d(paid).add(const Duration(days: 7)).toIso8601String().substring(0, 10),
  'remind_from': d(paid).subtract(const Duration(days: 7)).toIso8601String().substring(0, 10),
  'plan_name': 'Standard',
  'message': 'Pay ₹800 by UPI.',
  'contact': '98470 00000',
});

void main() {
  group('reference keys', () {
    test('case, spaces and dashes do not matter', () {
      expect(normalizeReferenceKey('demo 65yc 47x7 qmez'), 'DEMO-65YC-47X7-QMEZ');
      expect(normalizeReferenceKey(' DEMO-65YC-47X7-QMEZ '), 'DEMO-65YC-47X7-QMEZ');
      expect(normalizeReferenceKey('jm-abcd-efgh-ijkl'), 'JM-ABCD-EFGH-IJKL');
    });

    test('obvious typos are rejected before a network call', () {
      expect(normalizeReferenceKey(''), isNull);
      expect(normalizeReferenceKey('DEMO-65YC'), isNull);
    });

    test('each hosted business keeps its own login session', () {
      const a = BusinessConnection(businessName: 'A', baseUrl: 'https://api.x/b/alpha', anonKey: 'k', referenceKey: 'R');
      const b = BusinessConnection(businessName: 'B', baseUrl: 'https://api.x/b/beta', anonKey: 'k', referenceKey: 'R');
      expect(a.sessionKey, 'wf-session-alpha');
      expect(b.sessionKey, 'wf-session-beta');
      expect(
        BusinessConnection.fromJson({'base_url': 'https://api.x/b/c', 'anon_key': 'k'}),
        isNull,
        reason: 'a reference key is required',
      );
    });

    test('a saved connection survives a round trip; junk does not load', () {
      const c = BusinessConnection(businessName: 'JMJ', baseUrl: 'https://api.x/b/jmj', anonKey: 'k', referenceKey: 'JMJ-A');
      final back = BusinessConnection.fromJson(c.toJson())!;
      expect([back.businessName, back.baseUrl, back.anonKey, back.referenceKey], ['JMJ', 'https://api.x/b/jmj', 'k', 'JMJ-A']);
      expect(BusinessConnection.fromJson({'base_url': ''}), isNull);
    });
  });

  group('ControlApi.connect', () {
    test('finds the business for a key', () async {
      late Uri asked;
      final api = ControlApi(
        baseUrl: 'https://control.test',
        client: MockClient((req) async {
          asked = req.url;
          return http.Response(
            jsonEncode({
              'business_name': 'Demo Traders',
              'base_url': 'https://api.x/b/demo',
              'anon_key': 'anon',
              'state': 'active',
            }),
            200,
          );
        }),
      );
      final c = await api.connect('demo 65yc 47x7 qmez');
      expect(asked.queryParameters['key'], 'DEMO-65YC-47X7-QMEZ');
      expect(c.businessName, 'Demo Traders');
      expect(c.referenceKey, 'DEMO-65YC-47X7-QMEZ');
    });

    test("the server's message is shown for an unknown key", () async {
      final api = ControlApi(
        baseUrl: 'https://control.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 'UNKNOWN_KEY', 'message': 'No business has this reference key.'},
            }),
            404,
          ),
        ),
      );
      await expectLater(
        api.connect('DEMO-0000-0000-0000'),
        throwsA(isA<AppFailure>().having((f) => f.message, 'message', 'No business has this reference key.')),
      );
    });

    test('offline is a network failure', () async {
      final api = ControlApi(baseUrl: 'https://control.test', client: MockClient((_) => throw http.ClientException('down')));
      await expectLater(
        api.connect('DEMO-0000-0000-0000'),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.network)),
      );
    });
  });

  group('subscription ended (HTTP 402)', () {
    tearDown(() => AppFailure.onSubscriptionEnded = null);

    test('maps to subscriptionEnded with the renewal text and contact, and notifies', () {
      AppFailure? seen;
      AppFailure.onSubscriptionEnded = (f) => seen = f;
      final f = AppFailure.from(
        const ApiException(402, 'SUBSCRIPTION_ENDED', 'subscription_ended', details: 'Pay ₹800.', hint: '9847000000'),
      );
      expect(f.kind, FailureKind.subscriptionEnded);
      expect(f.detail, 'Pay ₹800.');
      expect(f.contact, '9847000000');
      expect(seen, same(f));
    });

    test('both apps send a paused session to /paused and back once renewed', () {
      const paused = AsyncData<Session>(Paused(message: 'm'));
      expect(ownerRedirectFor(paused, '/dashboard'), '/paused');
      expect(ownerRedirectFor(paused, '/paused'), isNull);
      expect(staffRedirectFor(paused, '/shops'), '/paused');
      expect(staffRedirectFor(paused, '/paused'), isNull);
    });
  });

  group('access state and banners', () {
    test('states follow the dates', () {
      final s = paidTo('2026-11-12');
      expect(s.stateOn(d('2026-11-01')), AccessState.active);
      expect(s.stateOn(d('2026-11-05')), AccessState.renewalDue);
      expect(s.stateOn(d('2026-11-12')), AccessState.renewalDue);
      expect(s.stateOn(d('2026-11-13')), AccessState.grace);
      expect(s.stateOn(d('2026-11-19')), AccessState.grace);
      expect(s.stateOn(d('2026-11-20')), AccessState.ended);
      expect(paidTo('2027-01-01', state: 'suspended').stateOn(d('2026-11-01')), AccessState.ended);
      expect(status.stateOn(d('2030-01-01')), AccessState.active, reason: 'no end date: not hosted');
    });

    test('owners see renewal due and grace; staff only grace', () {
      final s = paidTo('2026-11-12');
      expect(bannerFor(s, forOwner: true, today: d('2026-11-01')), isNull);
      final due = bannerFor(s, forOwner: true, today: d('2026-11-06'))!;
      expect(due.text, 'Your WholeFlow subscription ends on 12 Nov 2026. Pay ₹800 by UPI. 98470 00000');
      expect(due.urgent, isFalse);
      expect(bannerFor(s, forOwner: false, today: d('2026-11-06')), isNull);

      final grace = bannerFor(s, forOwner: true, today: d('2026-11-14'))!;
      expect(grace.text, startsWith('WholeFlow subscription ended on 12 Nov 2026. The app stops on 19 Nov 2026.'));
      expect(grace.urgent, isTrue);
      expect(
        bannerFor(s, forOwner: false, today: d('2026-11-14'))!.text,
        'WholeFlow subscription has ended. Ask your owner to renew it before 19 Nov 2026.',
      );
      expect(bannerFor(null, forOwner: true), isNull);
    });

    test('business today is the India date', () {
      expect(businessToday(DateTime.utc(2026, 10, 5, 19, 0)), d('2026-10-06'));
      expect(businessToday(DateTime.utc(2026, 10, 5, 18, 0)), d('2026-10-05'));
    });
  });
}
