import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../flutter_usb_serial_platform_interface.dart';
import 'usb_device.dart';
import 'usb_params.dart';
import 'usb_port.dart';

/// Desktop (Windows / Linux / macOS) implementation of the flutter_usb_serial
/// plugin.
///
/// All serial-port operations delegate to [flutter_libserialport], which wraps
/// the libserialport C library via dart:ffi. No platform channel is used.
///
/// Hot-plug detection is implemented with a 500 ms polling timer because
/// libserialport does not expose a hotplug API.
class FlutterUsbSerialDesktop extends FlutterUsbSerialPlatform {
  /// Called by the Flutter plugin registry when the plugin is loaded on a
  /// desktop platform.  Sets this class as the [FlutterUsbSerialPlatform]
  /// instance so that the platform interface registry is satisfied.
  static void registerWith() {
    FlutterUsbSerialPlatform.instance = FlutterUsbSerialDesktop();
  }

  // ── Device enumeration ──────────────────────────────────────────────────

  /// Returns all serial ports currently visible to the OS.
  static List<UsbDevice> getDevices() {
    final portNames = SerialPort.availablePorts;
    final devices = <UsbDevice>[];
    for (final name in portNames) {
      final port = SerialPort(name);
      try {
        devices.add(UsbDevice(
          deviceId: name.hashCode.abs(),
          deviceName: name,
          vendorId: port.vendorId ?? 0,
          productId: port.productId ?? 0,
          manufacturerName: port.manufacturer,
          productName: port.description ?? port.productName,
          serialNumber: port.serialNumber,
          driverType: _driverType(port),
          portCount: 1,
          hasPermission: true, // no permission model on desktop
        ));
      } finally {
        port.dispose();
      }
    }
    return devices;
  }

  // ── Device events (polling) ─────────────────────────────────────────────

  /// A broadcast stream that emits a fresh device snapshot whenever the set
  /// of available serial ports changes (checked every 500 ms).
  static Stream<List<UsbDevice>> get deviceEvents {
    late StreamController<List<UsbDevice>> controller;
    Timer? timer;
    List<String>? lastNames;

    void poll() {
      final current = List<String>.from(SerialPort.availablePorts)..sort();
      if (lastNames == null || !_listEq(current, lastNames!)) {
        lastNames = current;
        if (!controller.isClosed) {
          controller.add(getDevices());
        }
      }
    }

    controller = StreamController<List<UsbDevice>>.broadcast(
      onListen: () {
        lastNames =
            null; // force first emission so new listeners get a snapshot
        timer =
            Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );

    return controller.stream;
  }

  // ── Port management ──────────────────────────────────────────────────────

  /// Opens the serial port identified by [device.deviceName] and returns a
  /// [UsbPort] ready for I/O.
  ///
  /// Throws [PlatformException] if the port cannot be opened.
  static UsbPort openPort(
    UsbDevice device, {
    int baudRate = 9600,
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) {
    final port = SerialPort(device.deviceName);

    if (!port.openReadWrite()) {
      final err = SerialPort.lastError;
      port.dispose();
      throw PlatformException(
        code: 'OPEN_FAILED',
        message: err?.message ?? 'Could not open ${device.deviceName}',
      );
    }

    final config = SerialPortConfig();
    config.baudRate = baudRate;
    config.bits = dataBits;
    config.stopBits = stopBits;
    config.parity = parity;
    // NOTE: port.config= takes ownership of `config`; do NOT call config.dispose() here.
    port.config = config;

    return UsbPort.fromNativePort(port);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _driverType(SerialPort port) {
    switch (port.transport) {
      case SerialPortTransport.usb:
        final vid = port.vendorId;
        if (vid == 0x0403) return 'Ftdi';
        if (vid == 0x10C4) return 'Cp21xx';
        if (vid == 0x067B) return 'Prolific';
        if (vid == 0x1A86) return 'Ch34x';
        if (vid == 0x2341 || vid == 0x2A03) return 'CdcAcm'; // Arduino
        return 'UsbSerial';
      case SerialPortTransport.bluetooth:
        return 'Bluetooth';
      default:
        return 'Native';
    }
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
