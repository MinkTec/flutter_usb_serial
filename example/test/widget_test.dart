import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_usb_serial_example/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const UsbSerialApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
