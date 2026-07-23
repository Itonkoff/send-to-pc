import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:send_to_pc_mobile/app/mobile_app.dart';

void main() {
  testWidgets('mobile app renders share flow shell', (tester) async {
    await tester.pumpWidget(const SendToPcMobileApp());
    await tester.pump();

    expect(find.text('Send to PC'), findsOneWidget);
    expect(find.text('Ready to share'), findsOneWidget);
    expect(find.text('Paired computers'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Pair new computer'), findsOneWidget);
  });
}