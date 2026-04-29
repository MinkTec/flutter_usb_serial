/// Stub for FlutterUsbSerialDesktop — used on web where dart:ffi is unavailable.
library;

import 'usb_device.dart';
import 'usb_params.dart';
import 'usb_port.dart';

/// No-op stub — never called on web (all calls go through FlutterUsbSerialWeb).
class FlutterUsbSerialDesktop {
  static List<UsbDevice> getDevices() => [];
  static Stream<List<UsbDevice>> get deviceEvents => const Stream.empty();
  static Future<UsbPort> openPort(
    UsbDevice device, {
    int baudRate = 9600,
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) => throw UnsupportedError('Desktop not available on web');
}
