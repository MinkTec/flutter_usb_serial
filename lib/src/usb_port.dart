/// Abstract [UsbPort] base class and Android implementation.
///
/// The [UsbPort.fromNativePort] factory (desktop) is in `usb_port_native.dart`
/// and imported conditionally.  The [UsbPort.fromWebPort] factory (web) is in
/// `flutter_usb_serial_web.dart` and imported conditionally.
///
/// Concrete factories are wired by the stub / native / web conditional import
/// pattern so that the abstract file compiles on every platform.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'package:meta/meta.dart';

import 'usb_params.dart';

// Conditional import: on web we get the web factory; on native the FFI factory;
// stub throws on any unsupported platform.
import 'usb_port_factory_stub.dart'
    if (dart.library.ffi) 'usb_port_factory_native.dart'
    if (dart.library.js_interop) 'usb_port_factory_web.dart'
    as factory_impl;

/// An open USB serial port.
///
/// Obtain an instance by calling [FlutterUsbSerial.openPort].
/// Always call [close] when done to release the USB connection.
abstract class UsbPort {
  /// Protected constructor for subclasses only.
  @protected
  UsbPort.base();

  /// Internal factory for Android — uses the native method channel.
  factory UsbPort.fromPortId(int portId) => _UsbPortAndroid(portId);

  /// Internal factory for desktop — wraps a [SerialPort] from flutter_libserialport.
  static UsbPort fromNativePort(Object port) =>
      factory_impl.createFromNativePort(port);

  /// Internal factory for web — wraps a JS [SerialPort] object.
  static UsbPort fromWebPort(Object jsPort) =>
      factory_impl.createFromWebPort(jsPort);

  /// Raw bytes received from the device.
  ///
  /// Subscribe as soon as possible after opening the port.
  /// The stream closes automatically if the device is disconnected.
  Stream<Uint8List> get inputStream;

  // ── Port configuration ──────────────────────────────────────────────────

  /// Configure UART framing parameters.
  ///
  /// Can be called while the port is open to change parameters on-the-fly.
  Future<void> setParameters(
    int baudRate, {
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  });

  // ── Data transfer ───────────────────────────────────────────────────────

  /// Write [data] to the device.
  Future<void> write(Uint8List data);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Close the port and release the USB connection.
  Future<void> close();

  /// Returns `true` if the port is currently open.
  Future<bool> isOpen();

  // ── Control lines ───────────────────────────────────────────────────────

  /// Set the RTS (Request To Send) signal.
  Future<void> setRTS(bool value);

  /// Set the DTR (Data Terminal Ready) signal.
  Future<void> setDTR(bool value);

  /// Read the current state of all hardware control lines.
  ///
  /// Returns a map with keys: `RTS`, `CTS`, `DTR`, `DSR`, `CD`, `RI`.
  Future<Map<String, bool>> getControlLines();

  /// Returns the names of control lines supported by the current driver.
  ///
  /// Lines not in this list will throw [PlatformException] if used.
  Future<List<String>> getSupportedControlLines();

  // ── Advanced ────────────────────────────────────────────────────────────

  /// Set hardware/software flow control mode.
  Future<void> setFlowControl(UsbFlowControl mode);

  /// Discard bytes in the hardware TX and/or RX buffers.
  Future<void> purgeHwBuffers({
    bool purgeWriteBuffers = true,
    bool purgeReadBuffers = true,
  });

  /// Assert or de-assert a serial BREAK condition.
  Future<void> setBreak(bool value);
}

// ── Android implementation ─────────────────────────────────────────────────

class _UsbPortAndroid extends UsbPort {
  _UsbPortAndroid(int portId)
    : _portId = portId,
      inputStream = EventChannel(
        'flutter_usb_serial/read/$portId',
      ).receiveBroadcastStream().map((event) => event as Uint8List),
      super.base();

  final int _portId;
  static const _ch = MethodChannel('flutter_usb_serial');

  @override
  final Stream<Uint8List> inputStream;

  @override
  Future<void> setParameters(
    int baudRate, {
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) => _ch.invokeMethod<void>('setParameters', {
    'portId': _portId,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'stopBits': stopBits,
    'parity': parity,
  });

  @override
  Future<void> write(Uint8List data) =>
      _ch.invokeMethod<void>('write', {'portId': _portId, 'data': data});

  @override
  Future<void> close() =>
      _ch.invokeMethod<void>('closePort', {'portId': _portId});

  @override
  Future<bool> isOpen() async =>
      (await _ch.invokeMethod<bool>('isOpen', {'portId': _portId})) ?? false;

  @override
  Future<void> setRTS(bool value) =>
      _ch.invokeMethod<void>('setRTS', {'portId': _portId, 'value': value});

  @override
  Future<void> setDTR(bool value) =>
      _ch.invokeMethod<void>('setDTR', {'portId': _portId, 'value': value});

  @override
  Future<Map<String, bool>> getControlLines() async {
    final raw = await _ch.invokeMapMethod<String, bool>('getControlLines', {
      'portId': _portId,
    });
    return raw ?? {};
  }

  @override
  Future<List<String>> getSupportedControlLines() async {
    final raw = await _ch.invokeListMethod<String>('getSupportedControlLines', {
      'portId': _portId,
    });
    return raw ?? [];
  }

  @override
  Future<void> setFlowControl(UsbFlowControl mode) => _ch.invokeMethod<void>(
    'setFlowControl',
    {'portId': _portId, 'mode': mode.androidName},
  );

  @override
  Future<void> purgeHwBuffers({
    bool purgeWriteBuffers = true,
    bool purgeReadBuffers = true,
  }) => _ch.invokeMethod<void>('purgeHwBuffers', {
    'portId': _portId,
    'purgeWrite': purgeWriteBuffers,
    'purgeRead': purgeReadBuffers,
  });

  @override
  Future<void> setBreak(bool value) =>
      _ch.invokeMethod<void>('setBreak', {'portId': _portId, 'value': value});
}
