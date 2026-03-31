import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getDevices returns a list', (WidgetTester tester) async {
    final devices = await FlutterUsbSerial.getDevices();
    // Returns an empty list on emulators/devices with no USB serial connected.
    expect(devices, isList);
  });
}
