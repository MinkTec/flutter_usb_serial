/// Stub for FlutterUsbSerialWeb — used on non-web platforms.
library;

import 'usb_device.dart';
import 'usb_params.dart';
import 'usb_port.dart';

/// Always false on non-web platforms.
bool get webSerialSupported => false;

class FlutterUsbSerialWeb {
  FlutterUsbSerialWeb._();

  static Future<List<UsbDevice>> getDevices() =>
      throw UnsupportedError('Web Serial is not available on this platform.');

  static Stream<List<UsbDevice>> get deviceEvents =>
      throw UnsupportedError('Web Serial is not available on this platform.');

  static bool hasPermission(UsbDevice device) => false;

  static Future<bool> requestPermission(UsbDevice device) =>
      throw UnsupportedError('Web Serial is not available on this platform.');

  static Future<UsbPort> openPort(
    UsbDevice device, {
    int baudRate = 9600,
    int dataBits = 8,
    int stopBits = 1,
    int parity = 0,
    UsbFlowControl flowControl = UsbFlowControl.none,
    int bufferSize = 4096,
  }) => throw UnsupportedError('Web Serial is not available on this platform.');

  static const int kPickerSentinelId = -1;

  static UsbDevice get newDeviceSentinel =>
      throw UnsupportedError('Web Serial is not available on this platform.');
}
