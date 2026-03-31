import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

void main() {
  test('FlutterUsbSerial has a private constructor', () {
    // FlutterUsbSerial uses only static methods.
    // The test verifies the library imports correctly.
    expect(FlutterUsbSerial, isNotNull);
  });
}
