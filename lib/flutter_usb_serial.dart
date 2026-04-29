/// Flutter plugin for USB serial (COM port) communication.
///
/// Supports Android (via usb-serial-for-android), Windows / Linux / macOS
/// (via flutter_libserialport / libserialport), and **Web** (via the
/// [Web Serial API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API)).
///
/// Basic usage:
/// ```dart
/// // 1. List connected devices
/// final devices = await FlutterUsbSerial.getDevices();
///
/// // 2. Request USB permission if needed (Android only; always true on desktop/web)
/// if (!devices[0].hasPermission) {
///   await FlutterUsbSerial.requestPermission(devices[0]);
/// }
///
/// // 3. Open a port
/// final port = await FlutterUsbSerial.openPort(devices[0], baudRate: 115200);
///
/// // 4. Subscribe to incoming data
/// port.inputStream.listen((bytes) { /* handle Uint8List */ });
///
/// // 5. Send data
/// await port.write(Uint8List.fromList('hello\r\n'.codeUnits));
///
/// // 6. Close when done
/// await port.close();
/// ```
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'src/flutter_usb_serial_desktop_stub.dart'
    if (dart.library.ffi) 'src/flutter_usb_serial_desktop.dart';
import 'src/usb_device.dart';
import 'src/usb_params.dart';
import 'src/usb_port.dart';
import 'src/platform_stub.dart'
    if (dart.library.io) 'src/platform_native.dart'
    as platform_lib;
import 'src/flutter_usb_serial_web_stub.dart'
    if (dart.library.js_interop) 'src/flutter_usb_serial_web.dart'
    as web_impl;

export 'src/flutter_usb_serial_desktop_stub.dart'
    if (dart.library.ffi) 'src/flutter_usb_serial_desktop.dart';
export 'src/flutter_usb_serial_web_stub.dart'
    if (dart.library.js_interop) 'src/flutter_usb_serial_web.dart';
export 'src/usb_device.dart';
export 'src/usb_params.dart';
export 'src/usb_port.dart';

/// Main entry point for the flutter_usb_serial plugin.
class FlutterUsbSerial {
  FlutterUsbSerial._();

  // Android channels — only used when running natively on Android.
  static const _ch = MethodChannel('flutter_usb_serial');
  static const _devicesCh = EventChannel('flutter_usb_serial/devices');

  static bool get _isDesktop =>
      !kIsWeb && platform_lib.isDesktop;

  // ── Device enumeration ──────────────────────────────────────────────────

  /// Returns all currently connected USB serial devices.
  ///
  /// - **Android**: lists USB devices; [UsbDevice.hasPermission] reflects
  ///   whether the app has been granted access.
  /// - **Desktop**: lists available serial ports; [hasPermission] is always
  ///   `true`.
  /// - **Web**: lists ports the origin already has persistent permission for
  ///   (from prior user-gesture grants). Returns an empty list on a fresh
  ///   origin — call [openPort] with [FlutterUsbSerialWeb.newDeviceSentinel]
  ///   to trigger the browser port-picker.
  static Future<List<UsbDevice>> getDevices() async {
    if (kIsWeb) return web_impl.FlutterUsbSerialWeb.getDevices();
    if (_isDesktop) return FlutterUsbSerialDesktop.getDevices();
    final raw = await _ch.invokeListMethod<Object?>('getDevices');
    if (raw == null) return [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(UsbDevice.fromMap)
        .toList();
  }

  // ── Device events ────────────────────────────────────────────────────────

  /// A stream of device-list snapshots pushed whenever a USB serial device
  /// is attached or detached.
  ///
  /// Each event is the full list of currently connected USB serial devices
  /// at the moment of the change. On desktop and web, the stream polls every
  /// 500 ms since neither platform exposes native hotplug events.
  static Stream<List<UsbDevice>> get deviceEvents {
    if (kIsWeb) return web_impl.FlutterUsbSerialWeb.deviceEvents;
    if (_isDesktop) return FlutterUsbSerialDesktop.deviceEvents;
    return _devicesCh.receiveBroadcastStream().map((raw) {
      if (raw is! List) return <UsbDevice>[];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(UsbDevice.fromMap)
          .toList();
    });
  }

  // ── Permissions ─────────────────────────────────────────────────────────

  /// Returns `true` if the app already holds USB permission for [device].
  ///
  /// Always returns `true` on desktop and web.
  static Future<bool> hasPermission(UsbDevice device) async {
    if (kIsWeb || _isDesktop) return true;
    return (await _ch.invokeMethod<bool>('hasPermission', {
          'deviceId': device.deviceId,
        })) ??
        false;
  }

  /// Asks the user to grant USB permission for [device].
  ///
  /// - **Android**: shows the system permission dialog.
  /// - **Desktop**: always returns `true`.
  /// - **Web**: shows the browser's port-picker; **must** be called from a
  ///   synchronous user-gesture handler (e.g. a button's `onPressed`).
  static Future<bool> requestPermission(UsbDevice device) async {
    if (kIsWeb) return web_impl.FlutterUsbSerialWeb.requestPermission(device);
    if (_isDesktop) return true;
    return (await _ch.invokeMethod<bool>('requestPermission', {
          'deviceId': device.deviceId,
        })) ??
        false;
  }

  // ── Port management ──────────────────────────────────────────────────────

  /// Opens [portNumber] on [device] and configures the UART parameters.
  ///
  /// - **Android**: the device must already have USB permission.
  /// - **Desktop**: opens the port directly.
  /// - **Web**: if [device.deviceId] is [FlutterUsbSerialWeb.kPickerSentinelId]
  ///   (-1), the browser port-picker is shown (requires a user gesture).
  ///   Otherwise opens the pre-authorised port directly.
  ///
  /// Returns a [UsbPort] handle on success, or throws [PlatformException]
  /// on failure.
  static Future<UsbPort> openPort(
    UsbDevice device, {
    int portNumber = 0,
    int baudRate = 9600,
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) async {
    if (kIsWeb) {
      return web_impl.FlutterUsbSerialWeb.openPort(
        device,
        baudRate: baudRate,
        dataBits: dataBits,
        stopBits: stopBits,
        parity: parity,
      );
    }

    if (_isDesktop) {
      return FlutterUsbSerialDesktop.openPort(
        device,
        baudRate: baudRate,
        dataBits: dataBits,
        stopBits: stopBits,
        parity: parity,
      );
    }

    final portId = await _ch.invokeMethod<int>('openPort', {
      'deviceId': device.deviceId,
      'portNumber': portNumber,
      'baudRate': baudRate,
      'dataBits': dataBits,
      'stopBits': stopBits,
      'parity': parity,
    });
    if (portId == null) {
      throw PlatformException(
        code: 'OPEN_FAILED',
        message: 'openPort returned null portId',
      );
    }
    return UsbPort.fromPortId(portId);
  }
}
