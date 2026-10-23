import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/service_status_card.dart';

void main() {
  final startButton = find.byWidgetPredicate((widget) => widget is ElevatedButton);
  Widget card(
          {bool stopped = true,
          bool? connected = false,
          bool online = false,
          Future<void> Function()? start,
          double width = 200}) =>
      MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: width,
                  child: ServiceStatusCard(
                      stopped: stopped,
                      connected: connected,
                      online: online,
                      onStart: start ?? () async {},
                      text: (s) => s))));

  testWidgets('stopped service overrides a stale online flag', (tester) async {
    await tester.pumpWidget(card(online: true));
    expect(find.text('Connections unavailable'), findsOneWidget);
    expect(find.text('Ready for support'), findsNothing);
    expect(find.text('Enable support service'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing IPC offers start even when saved setting is enabled',
      (tester) async {
    await tester.pumpWidget(card(stopped: false));
    expect(find.text('Enable support service'), findsOneWidget);
  });

  testWidgets(
      'waits for real service confirmation and prevents duplicate starts',
      (tester) async {
    var calls = 0;
    Future<void> start() async {
      calls++;
    }

    await tester.pumpWidget(card(start: start));
    await tester.tap(startButton);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<ElevatedButton>(startButton).onPressed,
        isNull);
    expect(find.text('Starting support service…'), findsOneWidget);
    await tester
        .pumpWidget(card(stopped: false, connected: true, start: start));
    expect(find.text('Waiting for connection'), findsOneWidget);
    expect(find.text('Ready for support'), findsNothing);
    await tester
        .pumpWidget(card(stopped: false, connected: true, online: true));
    expect(find.text('Ready for support'), findsOneWidget);
  });

  testWidgets('cancelled elevation times out and allows retry', (tester) async {
    await tester.pumpWidget(card());
    await tester.tap(startButton);
    await tester.pump(const Duration(seconds: 21));
    expect(
        find.text(
            'Service did not start. Confirm the system permission prompt and try again.'),
        findsOneWidget);
    expect(tester.widget<ElevatedButton>(startButton).onPressed,
        isNotNull);
  });

  testWidgets('start exception is visible and disposal cancels the timer',
      (tester) async {
    await tester.pumpWidget(card(start: () async {
      throw StateError('denied');
    }));
    await tester.tap(startButton);
    await tester.pump();
    expect(find.text('Connections unavailable'), findsOneWidget);
    expect(
        find.text(
            'Service did not start. Confirm the system permission prompt and try again.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 21));
    expect(tester.takeException(), isNull);
  });
}
