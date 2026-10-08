import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wholeflow_app/core/api/api_client.dart';
import 'package:wholeflow_app/core/errors/app_failure.dart';
import 'package:wholeflow_app/core/money/money.dart';
import 'package:wholeflow_app/features/analytics/data/analytics_repository.dart';
import 'package:wholeflow_app/features/analytics/domain/payment_analysis.dart';

void main() {
  late http.Request last;
  ApiClient client(int status, Object body, {String? token = 'tok'}) => ApiClient(
    baseUrl: 'https://api.example.test/b/demo',
    token: () async => token,
    client: MockClient((req) async {
      last = req;
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    }),
  );

  test('calls <base>/api/v1/<path> with the login token', () async {
    final out = await client(200, {'ok': true}).get('payments', {'company': 'c1', 'credit_days': '30'});
    expect(out['ok'], isTrue);
    expect(last.url.toString(), 'https://api.example.test/b/demo/api/v1/payments?company=c1&credit_days=30');
    expect(last.headers['Authorization'], 'Bearer tok');
  });

  test('a paused business becomes the paused screen, with the owner message', () async {
    AppFailure? seen;
    AppFailure.onSubscriptionEnded = (f) => seen = f;
    addTearDown(() => AppFailure.onSubscriptionEnded = null);
    final repo = AnalyticsRepository(
      client(402, {
        'error': {
          'code': 'SUBSCRIPTION_ENDED',
          'message': 'subscription_ended',
          'details': 'Renew to continue',
          'hint': '98000 00000',
        },
      }),
    );
    await expectLater(
      repo.summary('c1', creditDays: 30),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.subscriptionEnded)),
    );
    expect(seen?.detail, 'Renew to continue');
    expect(seen?.contact, '98000 00000');
  });

  test('errors map to the usual failures', () {
    expect(AppFailure.from(const ApiException(401, 'UNAUTHENTICATED', 'x')).kind, FailureKind.unauthenticated);
    expect(
      AppFailure.from(const ApiException(403, 'NOT_OWNER', 'Only the owner can see payment insights.')).message,
      'Only the owner can see payment insights.',
    );
    expect(AppFailure.from(const ApiException(404, 'NOT_FOUND', 'x')).kind, FailureKind.notFound);
    expect(AppFailure.from(const ApiException(500, 'SERVER_ERROR', 'x')).kind, FailureKind.server);
  });

  test('signed out: no request is made', () async {
    await expectLater(client(200, {}, token: null).get('payments'), throwsA(isA<ApiException>()));
  });

  test('reads the payment summary and a shop as the server sends them', () {
    final s = BusinessPaymentSummary.fromJson({
      'credit_days': 30,
      'today': '2026-07-20',
      'overdue': '1100.00',
      'overdue_shops': 1,
      'open_amount': '1100.00',
      'ageing': {'d1_30': '800.00', 'd31_60': '300.00'},
      'on_time_rate': null,
      'avg_days_to_pay': 42.5,
      'overdue_month_ago': '1500.00',
      'shops': [
        {
          'shop': {
            'id': 's1',
            'name': 'Alpha',
            'site_name': 'Town',
            'phone': null,
            'opening': '1000.00',
            'receivable': '1100.00',
          },
          'advance': '0.00',
          'overdue': '1100.00',
          'open_amount': '1100.00',
          'open_bills': 2,
          'max_days_overdue': 50,
          'ageing': {'d1_30': '800.00', 'd31_60': '300.00'},
          'paid_bills': 1,
          'on_time_bills': 0,
          'on_time_rate': 0,
          'avg_days_to_pay': 100,
          'last_payment_date': '2026-07-10',
          'last_payment_amount': '1200.00',
          'computed_balance': '1100.00',
          'reconciled': true,
        },
      ],
    });
    expect(s.overdue, const Money(110000));
    expect(s.overdueMonthAgo, const Money(150000));
    expect(s.ageing[AgeBucket.d31to60], const Money(30000));
    expect(s.ageing[AgeBucket.d90plus], Money.zero);
    expect(s.onTimeRate, isNull);
    final p = s.shops.single;
    expect(p.shop.siteName, 'Town');
    expect(p.status, PaymentStatus.late);
    expect(p.habit(30), PayHabit.veryLate);
    expect(p.lastPaymentDate, DateTime(2026, 7, 10));
    expect(p.today, DateTime(2026, 7, 20));

    final shop = ShopPayments.fromJson({
      'shop': {'id': 's1', 'name': 'Alpha', 'opening': '0', 'receivable': '0'},
      'credit_days': 30,
      'today': '2026-07-20',
      'closed_bills': 1,
      'bills': [
        {
          'date': '2026-04-01',
          'due': '2026-05-01',
          'amount': '1000.00',
          'remaining': '0.00',
          'voucher': 'Opening balance',
          'is_opening': true,
          'settled_on': '2026-07-10',
          'allocations': [
            {'date': '2026-07-10', 'amount': '1000.00', 'kind': 'payment'},
          ],
        },
      ],
    });
    final b = shop.profile.bills.single;
    expect(b.isOpen, isFalse);
    expect(b.paidByReceipt, isTrue);
    expect(b.settledOnTime, isFalse);
    expect(shop.closedBills, 1);
  });
}
