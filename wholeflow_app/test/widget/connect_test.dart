import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wholeflow_app/core/connection/business_connection.dart';
import 'package:wholeflow_app/core/connection/connect_screen.dart';

void main() {
  ControlApi api() => ControlApi(
    baseUrl: 'https://control.test',
    client: MockClient((req) async {
      if (req.url.queryParameters['key'] == 'DEMO-65YC-47X7-QMEZ') {
        return http.Response(
          jsonEncode({
            'business_name': 'Demo Traders',
            'base_url': 'https://api.x/b/demo',
            'anon_key': 'anon',
            'state': 'active',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'error': {'code': 'UNKNOWN_KEY', 'message': 'No business has this reference key. Check it and try again.'},
        }),
        404,
      );
    }),
  );

  testWidgets('someone without a key is pointed to the website', (tester) async {
    await tester.pumpWidget(ConnectApp(title: 'WholeFlow Owner', api: api(), onConnected: (_) async {}));
    expect(find.text("Don't have a key?"), findsOneWidget);
    expect(find.byKey(const Key('connect-website')), findsOneWidget);
    expect(find.text('wholeflow.jitsuji.xyz'), findsOneWidget);
    expect(wholeflowWebsite, 'https://wholeflow.jitsuji.xyz/');
  });

  testWidgets('a reference key finds the business, Connect saves it', (tester) async {
    BusinessConnection? connected;
    await tester.pumpWidget(ConnectApp(title: 'WholeFlow Owner', api: api(), onConnected: (c) async => connected = c));

    await tester.enterText(find.byKey(const Key('connect-key')), 'demo-0000-0000-0000');
    await tester.tap(find.byKey(const Key('connect-continue')));
    await tester.pumpAndSettle();
    expect(find.text('No business has this reference key. Check it and try again.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('connect-key')), 'demo 65yc 47x7 qmez');
    await tester.tap(find.byKey(const Key('connect-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Demo Traders'), findsOneWidget);
    expect(connected, isNull, reason: 'nothing is saved before Connect');

    await tester.tap(find.byKey(const Key('connect-confirm')));
    await tester.pump(); // the app then replaces this screen; the spinner keeps going here
    expect(connected?.baseUrl, 'https://api.x/b/demo');
    expect(connected?.referenceKey, 'DEMO-65YC-47X7-QMEZ');
  });

  testWidgets('Use a different key goes back to the key field', (tester) async {
    await tester.pumpWidget(ConnectApp(title: 'WholeFlow Staff', api: api(), onConnected: (_) async {}));
    await tester.enterText(find.byKey(const Key('connect-key')), 'DEMO-65YC-47X7-QMEZ');
    await tester.tap(find.byKey(const Key('connect-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a different key'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connect-key')), findsOneWidget);
    expect(find.byKey(const Key('connect-scan')), findsOneWidget);
  });
}
