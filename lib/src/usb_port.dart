import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'usb_params.dart';

/// An open USB serial port.
///
/// Obtain an instance by calling [FlutterUsbSerial.openPort].
/// Always call [close] when done to release the USB connection.
class UsbPort {
  /// Internal constructor — use [FlutterUsbSerial.openPort] to obtain a port.
  UsbPort.fromPortId(int portId)
      : _portId = portId,
        inputStream = EventChannel('flutter_usb_serial/read/$portId')
            .receiveBroadcastStream()
            .map((event) => event as Uint8List);

  final int _portId;
  static const _ch = MethodChannel('flutter_usb_serial');

  /// Raw bytes received from the device.
  ///
  /// Subscribe as soon as possible after opening the port. A small ring buffer
  /// (50 packets) retains data received before the first subscriber attaches.
  ///
  /// The stream closes automatically if the device is disconnected.
  final Stream<Uint8List> inputStream;

  // ── Port configuration ──────────────────────────────────────────────────

  /// Configure UART framing parameters.
  ///
  /// Can be called while the port is open to change parameters on-the-fly.
  Future<void> setParameters(
    int baudRate, {
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) =>
      _ch.invokeMethod<void>('setParameters', {
        'portId': _portId,
        'baudRate': baudRate,
        'dataBits': dataBits,
        'stopBits': stopBits,
        'parity': parity,
      });

  // ── Data transfer ───────────────────────────────────────────────────────

  /// Write [data] to the device (2 s timeout).
  Future<void> write(Uint8List data) =>
      _ch.invokeMethod<void>('write', {'portId': _portId, 'data': data});

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Close the port and release the USB connection.
  Future<void> close() =>
      _ch.invokeMethod<void>('closePort', {'portId': _portId});

  /// Returns `true` if the port is currently open.
  Future<bool> isOpen() async =>
      (await _ch.invokeMethod<bool>('isOpen', {'portId': _portId})) ?? false;

  // ── Control lines ───────────────────────────────────────────────────────

  /// Set the RTS (Request To Send) signal.
  Future<void> setRTS(bool value) =>
      _ch.invokeMethod<void>('setRTS', {'portId': _portId, 'value': value});

  /// Set the DTR (Data Terminal Ready) signal.
  Future<void> setDTR(bool value) =>
      _ch.invokeMethod<void>('setDTR', {'portId': _portId, 'value': value});

  /// Read the current state of all hardware control lines.
  ///
  /// Returns a map with keys: `RTS`, `CTS`, `DTR`, `DSR`, `CD`, `RI`.
  Future<Map<String, bool>> getControlLines() async {
    final raw = await _ch.invokeMapMethod<String, bool>(
      'getControlLines',
      {'portId': _portId},
    );
    return raw ?? {};
  }

  /// Returns the names of control lines supported by the current driver.
  ///
  /// Lines not in this list will throw [PlatformException] if used.
  Future<List<String>> getSupportedControlLines() async {
    final raw = await _ch.invokeListMethod<String>(
      'getSupportedControlLines',
      {'portId': _portId},
    );
    return raw ?? [];
  }

  // ── Advanced ────────────────────────────────────────────────────────────

  /// Set hardware/software flow control mode.
  Future<void> setFlowControl(UsbFlowControl mode) =>
      _ch.invokeMethod<void>('setFlowControl', {
        'portId': _portId,
        'mode': mode.androidName,
      });

  /// Discard bytes in the hardware TX and/or RX buffers.
  Future<void> purgeHwBuffers({
    bool purgeWriteBuffers = true,
    bool purgeReadBuffers = true,
  }) =>
      _ch.invokeMethod<void>('purgeHwBuffers', {
        'portId': _portId,
        'purgeWrite': purgeWriteBuffers,
        'purgeRead': purgeReadBuffers,
      });

  /// Assert or de-assert a serial BREAK condition.
  Future<void> setBreak(bool value) =>
      _ch.invokeMethod<void>('setBreak', {'portId': _portId, 'value': value});
}
