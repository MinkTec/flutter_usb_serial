/// Web implementation of flutter_usb_serial using the Web Serial API.
///
/// The Web Serial API requires a user gesture to call [requestPort].
/// [getDevices] returns ports the origin already has persistent permission for
/// (granted from a previous session). The first time a user connects they must
/// use the picker exposed by [openPort].
///
/// Supported browsers (as of 2025): Chrome 89+, Edge 89+, Opera 75+.
/// Firefox and Safari do NOT support Web Serial.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/services.dart';

import '../flutter_usb_serial_platform_interface.dart';
import 'usb_device.dart';
import 'usb_params.dart';
import 'usb_port.dart';
import 'web_serial_interop.dart';

export 'web_serial_interop.dart' show webSerialSupported;

/// Dart plugin class registration entry point for web.
class FlutterUsbSerialWeb extends FlutterUsbSerialPlatform {
  static void registerWith([Object? registrar]) {
    FlutterUsbSerialPlatform.instance = FlutterUsbSerialWeb();
  }

  // ── Device enumeration ─────────────────────────────────────────────────────

  /// Returns all ports the origin already has permission for.
  ///
  /// On a fresh origin this will be empty. Use [openPort] (which triggers
  /// the browser's port-picker) to let the user grant access to a device.
  static Future<List<UsbDevice>> getDevices() async {
    if (!webSerialSupported) return [];
    final jsArray = await navigatorSerial.getPorts().toDart;
    final ports = jsArray.toDart;
    final devices = <UsbDevice>[];
    for (var i = 0; i < ports.length; i++) {
      final info = await ports[i].getInfo().toDart;
      devices.add(_deviceFromInfo(i, info));
    }
    return devices;
  }

  /// Web Serial has no native hotplug events — poll every 500 ms like desktop.
  static Stream<List<UsbDevice>> get deviceEvents {
    late StreamController<List<UsbDevice>> controller;
    Timer? timer;
    List<int>? lastIds;

    Future<void> poll() async {
      final current = await getDevices();
      final ids = current.map((d) => d.deviceId).toList()..sort();
      if (lastIds == null || !_listEq(ids, lastIds!)) {
        lastIds = ids;
        if (!controller.isClosed) controller.add(current);
      }
    }

    controller = StreamController<List<UsbDevice>>.broadcast(
      onListen: () {
        lastIds = null;
        timer = Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Web Serial: permission is implicitly granted by the picker. Always true.
  static bool hasPermission(UsbDevice device) => true;

  /// Shows the port picker. Must be called from a user-gesture context.
  static Future<bool> requestPermission(UsbDevice device) async {
    if (!webSerialSupported) return false;
    try {
      await navigatorSerial.requestPort().toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Open port ──────────────────────────────────────────────────────────────

  /// Opens a serial port.
  ///
  /// - If [device] was obtained from [getDevices], the corresponding port is
  ///   opened directly (no picker shown).
  /// - If [device.deviceId] == [kPickerSentinelId], the browser's native
  ///   port-picker dialog is shown first.
  ///
  /// **Must be called from a synchronous user-gesture handler** on web because
  /// the browser requires user activation for [requestPort].
  static Future<UsbPort> openPort(
    UsbDevice device, {
    int baudRate = 9600,
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
    UsbFlowControl flowControl = UsbFlowControl.none,
    int bufferSize = 4096,
  }) async {
    if (!webSerialSupported) {
      throw PlatformException(
        code: 'UNSUPPORTED',
        message: 'Web Serial API is not supported in this browser. '
            'Use Chrome 89+ or Edge 89+.',
      );
    }

    SerialPort jsPort;

    if (device.deviceId == kPickerSentinelId) {
      // Show the browser port picker — requires user gesture.
      try {
        jsPort = await navigatorSerial.requestPort().toDart;
      } on JSObject catch (e) {
        throw PlatformException(
          code: 'PERMISSION_DENIED',
          message: _extractJsError(e),
        );
      }
    } else {
      // Re-use a port we already have permission for.
      final jsArray = await navigatorSerial.getPorts().toDart;
      final ports = jsArray.toDart;
      if (device.deviceId < 0 || device.deviceId >= ports.length) {
        throw PlatformException(
          code: 'DEVICE_NOT_FOUND',
          message: 'Device at index ${device.deviceId} is no longer available.',
        );
      }
      jsPort = ports[device.deviceId];
    }

    final options = SerialOptions(
      baudRate: baudRate,
      dataBits: dataBits,
      stopBits: stopBits == UsbStopBits.onePointFive ? 1 : stopBits,
      parity: _parityName(parity),
      bufferSize: bufferSize,
      flowControl: _flowControlName(flowControl),
    );
    try {
      await jsPort.open(options).toDart;
    } on JSObject catch (e) {
      throw PlatformException(
        code: 'OPEN_FAILED',
        message: _extractJsError(e),
      );
    }

    return UsbPort.fromWebPort(jsPort);
  }

  // ── "Pick new device" sentinel ─────────────────────────────────────────────

  /// Sentinel value for [UsbDevice.deviceId] that causes [openPort] to show
  /// the browser's native port-picker dialog.
  static const int kPickerSentinelId = -1;

  /// A [UsbDevice] sentinel that, when passed to [openPort], shows the browser
  /// port-picker instead of opening a pre-authorised port.
  ///
  /// Add this entry to the device list in your UI to offer a
  /// "Connect new device…" option.
  static UsbDevice get newDeviceSentinel => const UsbDevice(
    deviceId: kPickerSentinelId,
    deviceName: '',
    vendorId: 0,
    productId: 0,
    driverType: 'WebSerial',
    portCount: 1,
    hasPermission: true,
    productName: 'Connect new device…',
  );

  // ── Private helpers ────────────────────────────────────────────────────────

  static UsbDevice _deviceFromInfo(int index, SerialPortInfo info) {
    final vid = info.usbVendorId ?? 0;
    return UsbDevice(
      deviceId: index,
      deviceName: 'Serial Port $index',
      vendorId: vid,
      productId: info.usbProductId ?? 0,
      serialNumber: info.usbSerialNumber,
      driverType: _driverType(vid),
      portCount: 1,
      hasPermission: true,
    );
  }

  static String _driverType(int vid) => switch (vid) {
    0x0403 => 'Ftdi',
    0x10C4 => 'Cp21xx',
    0x067B => 'Prolific',
    0x1A86 => 'Ch34x',
    0x2341 || 0x2A03 => 'CdcAcm',
    _ => 'WebSerial',
  };

  static String _parityName(int parity) => switch (parity) {
    UsbParity.odd  => 'odd',
    UsbParity.even => 'even',
    _              => 'none',
  };

  static String _flowControlName(UsbFlowControl fc) =>
      fc == UsbFlowControl.rtsCts ? 'hardware' : 'none';

  static String _extractJsError(JSObject e) {
    try {
      // dartify() converts a JS object to a Dart Map<String, dynamic>.
      // DOMException / Error both have a `message` string property.
      final dart = e.dartify();
      if (dart is Map) {
        final msg = dart['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return e.toString();
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── _UsbPortWeb ────────────────────────────────────────────────────────────

/// Web Serial implementation of [UsbPort].
///
/// Internally:
/// - Pumps a [ReadableStreamDefaultReader] in a Dart async loop → [inputStream]
/// - Holds a [WritableStreamDefaultWriter] for [write]
/// - Uses [SerialPort.setSignals] / [getSignals] for control-line I/O
///
/// Instances are created via [UsbPort.fromWebPort].
class UsbPortWeb extends UsbPort {
  /// Creates a [UsbPortWeb] from an already-open JS [SerialPort].
  ///
  /// Called by [usb_port_factory_web.dart] via [UsbPort.fromWebPort].
  // ignore: library_private_types_in_public_api
  UsbPortWeb.fromOpenPort(SerialPort jsPort) : this._(jsPort);

  UsbPortWeb._(this._jsPort)
      : _inputController = StreamController<Uint8List>.broadcast(),
        super.base() {
    _startReading();
  }

  final SerialPort _jsPort;
  final StreamController<Uint8List> _inputController;

  ReadableStreamDefaultReader? _reader;
  WritableStreamDefaultWriter? _writer;
  bool _closed = false;

  // Local shadow of output signal states (Web Serial does not expose them back).
  bool _rtsState = false;
  bool _dtrState = false;

  // Last-known serial options — stored so we can re-open with same settings
  // after a setParameters call (Web Serial requires close/re-open).
  SerialOptions _lastOptions = SerialOptions(baudRate: 9600);

  @override
  Stream<Uint8List> get inputStream => _inputController.stream;

  // ── Read loop ──────────────────────────────────────────────────────────────

  void _startReading() {
    final readable = _jsPort.readable;
    if (readable == null) return;
    _reader = readable.getReader();
    _pumpReads();
  }

  Future<void> _pumpReads() async {
    final reader = _reader;
    if (reader == null) return;
    while (!_closed) {
      try {
        final result = await reader.read().toDart;
        if (result.done) break;
        final jsBytes = result.value;
        if (jsBytes != null && !_inputController.isClosed) {
          _inputController.add(jsBytes.toDart);
        }
      } catch (e) {
        if (!_closed && !_inputController.isClosed) {
          _inputController.addError(e);
        }
        break;
      }
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  @override
  Future<void> write(Uint8List data) async {
    final writable = _jsPort.writable;
    if (writable == null) {
      throw PlatformException(
        code: 'WRITE_FAILED',
        message: 'Port writable stream is null.',
      );
    }
    _writer ??= writable.getWriter();
    await _writer!.ready.toDart;
    await _writer!.write(data.toJS).toDart;
  }

  // ── Serial parameters (requires close/re-open) ─────────────────────────────

  @override
  Future<void> setParameters(
    int baudRate, {
    int dataBits = UsbDataBits.bits8,
    int stopBits = UsbStopBits.one,
    int parity = UsbParity.none,
  }) async {
    _lastOptions = SerialOptions(
      baudRate: baudRate,
      dataBits: dataBits,
      stopBits: stopBits == UsbStopBits.onePointFive ? 1 : stopBits,
      parity: _parityName(parity),
    );
    await _releaseStreams();
    await _jsPort.close().toDart;

    await _jsPort.open(_lastOptions).toDart;
    _startReading();
  }

  // ── Close ──────────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _releaseStreams();
    try {
      await _jsPort.close().toDart;
    } catch (_) {
      // Port may already be detached.
    }
    if (!_inputController.isClosed) await _inputController.close();
  }

  Future<void> _releaseStreams() async {
    final writer = _writer;
    _writer = null;
    if (writer != null) {
      try { writer.releaseLock(); } catch (_) {}
    }

    final reader = _reader;
    _reader = null;
    if (reader != null) {
      try { await reader.cancel().toDart; } catch (_) {}
      try { reader.releaseLock(); } catch (_) {}
    }
  }

  // ── State ──────────────────────────────────────────────────────────────────

  @override
  Future<bool> isOpen() async => _jsPort.readable != null && !_closed;

  // ── Control lines ──────────────────────────────────────────────────────────

  @override
  Future<void> setRTS(bool value) async {
    _rtsState = value;
    await _jsPort.setSignals(SerialOutputSignals(requestToSend: value)).toDart;
  }

  @override
  Future<void> setDTR(bool value) async {
    _dtrState = value;
    await _jsPort
        .setSignals(SerialOutputSignals(dataTerminalReady: value))
        .toDart;
  }

  @override
  Future<Map<String, bool>> getControlLines() async {
    final input = await _jsPort.getSignals().toDart;
    return {
      'RTS': _rtsState,
      'CTS': input.clearToSend,
      'DTR': _dtrState,
      'DSR': input.dataSetReady,
      'CD': input.dataCarrierDetect,
      'RI': input.ringIndicator,
    };
  }

  @override
  Future<List<String>> getSupportedControlLines() async =>
      ['RTS', 'CTS', 'DTR', 'DSR', 'CD', 'RI'];

  // ── Flow control ───────────────────────────────────────────────────────────

  /// Web Serial flow control is configured at [open] time. Changing it after
  /// opening requires a close/re-open, which would need baud-rate knowledge.
  /// For now this is a no-op — pass [flowControl] to [FlutterUsbSerialWeb.openPort].
  @override
  Future<void> setFlowControl(UsbFlowControl mode) async {}

  // ── Buffer operations ──────────────────────────────────────────────────────

  /// Web Serial has no buffer-flush API.
  @override
  Future<void> purgeHwBuffers({
    bool purgeWriteBuffers = true,
    bool purgeReadBuffers = true,
  }) async {}

  // ── Break ──────────────────────────────────────────────────────────────────

  @override
  Future<void> setBreak(bool value) async {
    // The JS property is named `break` (reserved Dart keyword).
    // We use setSignals with the break_ field mapped to `break` by the interop.
    await _jsPort.setSignals(SerialOutputSignals(break_: value)).toDart;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _parityName(int parity) => switch (parity) {
    UsbParity.odd  => 'odd',
    UsbParity.even => 'even',
    _              => 'none',
  };
}
