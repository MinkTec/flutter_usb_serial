/// Native (desktop) factory — compiled only when dart:ffi is available.
///
/// Imports flutter_libserialport and constructs [_UsbPortDesktop].
/// The web factory is a no-op stub on this platform.
library;

import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'usb_params.dart';
import 'usb_port.dart';

UsbPort createFromNativePort(Object port) =>
    _UsbPortDesktop(port as SerialPort);

UsbPort createFromWebPort(Object jsPort) =>
    throw UnsupportedError('fromWebPort is not supported on native platforms.');

// ── Desktop implementation (Windows / Linux / macOS) ───────────────────────

class _UsbPortDesktop extends UsbPort {
  _UsbPortDesktop(this._port) : super.base() {
    _reader = SerialPortReader(_port);
    inputStream = _reader.stream;
  }

  final SerialPort _port;
  late final SerialPortReader _reader;

  @override
  late final Stream<Uint8List> inputStream;

  @override
  Future<void> setParameters(
    int baudRate, {
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) async {
    final config = SerialPortConfig();
    config.baudRate = baudRate;
    config.bits = dataBits;
    // UsbStopBits: one=1, two=2, onePointFive=3  →  libserialport: 1, 2, 3 (same values)
    config.stopBits = stopBits;
    // UsbParity: none=0,odd=1,even=2,mark=3,space=4 → SerialPortParity same values
    config.parity = parity;
    // NOTE: _port.config= takes ownership of `config`; do NOT call config.dispose() here.
    _port.config = config;
  }

  @override
  Future<void> write(Uint8List data) async {
    final written = _port.write(data, timeout: 2000);
    if (written < 0) {
      throw PlatformException(
        code: 'WRITE_FAILED',
        message: SerialPort.lastError?.message,
      );
    }
  }

  @override
  Future<void> close() async {
    _reader.close();
    _port.close();
    _port.dispose();
  }

  @override
  Future<bool> isOpen() async => _port.isOpen;

  @override
  Future<void> setRTS(bool value) async {
    final config = SerialPortConfig();
    config.rts = value ? SerialPortRts.on : SerialPortRts.off;
    // NOTE: _port.config= takes ownership; do NOT call config.dispose() here.
    _port.config = config;
  }

  @override
  Future<void> setDTR(bool value) async {
    final config = SerialPortConfig();
    config.dtr = value ? SerialPortDtr.on : SerialPortDtr.off;
    // NOTE: _port.config= takes ownership; do NOT call config.dispose() here.
    _port.config = config;
  }

  @override
  Future<Map<String, bool>> getControlLines() async {
    // _port.config returns the port-owned config; do NOT dispose it.
    final config = _port.config;
    final rtsOn = config.rts == SerialPortRts.on;
    final dtrOn = config.dtr == SerialPortDtr.on;

    int signals = 0;
    try {
      signals = _port.signals;
    } catch (_) {
      // Some drivers do not support reading modem status lines.
    }

    return {
      'RTS': rtsOn,
      'CTS': (signals & SerialPortSignal.cts) != 0,
      'DTR': dtrOn,
      'DSR': (signals & SerialPortSignal.dsr) != 0,
      'CD': (signals & SerialPortSignal.dcd) != 0,
      'RI': (signals & SerialPortSignal.ri) != 0,
    };
  }

  @override
  Future<List<String>> getSupportedControlLines() async => [
    'RTS',
    'CTS',
    'DTR',
    'DSR',
    'CD',
    'RI',
  ];

  @override
  Future<void> setFlowControl(UsbFlowControl mode) async {
    final config = SerialPortConfig();
    switch (mode) {
      case UsbFlowControl.none:
        config.setFlowControl(SerialPortFlowControl.none);
      case UsbFlowControl.rtsCts:
        config.setFlowControl(SerialPortFlowControl.rtsCts);
      case UsbFlowControl.dtrDsr:
        config.setFlowControl(SerialPortFlowControl.dtrDsr);
      case UsbFlowControl.xonXoff:
      case UsbFlowControl.xonXoffInline:
        // libserialport has a single XON/XOFF mode; inline is the closest match.
        config.setFlowControl(SerialPortFlowControl.xonXoff);
    }
    _port.config = config;
  }

  @override
  Future<void> purgeHwBuffers({
    bool purgeWriteBuffers = true,
    bool purgeReadBuffers = true,
  }) async {
    if (purgeWriteBuffers && purgeReadBuffers) {
      _port.flush(SerialPortBuffer.both);
    } else if (purgeWriteBuffers) {
      _port.flush(SerialPortBuffer.output);
    } else if (purgeReadBuffers) {
      _port.flush(SerialPortBuffer.input);
    }
  }

  @override
  Future<void> setBreak(bool value) async {
    if (value) {
      _port.startBreak();
    } else {
      _port.endBreak();
    }
  }
}
