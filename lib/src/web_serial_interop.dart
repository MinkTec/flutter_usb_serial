/// dart:js_interop bindings for the Web Serial API.
///
/// Spec: https://wicg.github.io/serial/
/// MDN:  https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API
///
/// These are typed external declarations only — no implementation code.
/// All types are JSObject extensions as required by dart:js_interop.
library;

import 'dart:js_interop';

// ── navigator.serial ────────────────────────────────────────────────────────

@JS('navigator.serial')
external Serial get navigatorSerial;

/// Returns true when the browser exposes the Web Serial API.
bool get webSerialSupported {
  // navigator.serial is undefined in unsupported browsers.
  return _hasSerial();
}

@JS('eval')
external JSAny? _jsEval(JSString code);

bool _hasSerial() {
  try {
    final result = _jsEval(
      "'serial' in navigator && navigator.serial !== undefined".toJS,
    );
    return (result as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

// ── Serial (navigator.serial) ────────────────────────────────────────────────

extension type Serial._(JSObject _) implements JSObject {
  /// Prompt the user to select a serial port.
  ///
  /// Returns a [SerialPort] the user selected.
  /// Throws [DOMException] if the user dismisses the picker or access is denied.
  external JSPromise<SerialPort> requestPort([SerialPortRequestOptions? options]);

  /// Returns all [SerialPort] objects that the origin already has permission for.
  external JSPromise<JSArray<SerialPort>> getPorts();
}

// ── SerialPortRequestOptions ─────────────────────────────────────────────────

extension type SerialPortRequestOptions._(JSObject _) implements JSObject {
  external factory SerialPortRequestOptions({JSArray<SerialPortFilter>? filters});
}

extension type SerialPortFilter._(JSObject _) implements JSObject {
  external factory SerialPortFilter({int? usbVendorId, int? usbProductId});
}

// ── SerialPort ───────────────────────────────────────────────────────────────

extension type SerialPort._(JSObject _) implements JSObject {
  /// Open the port with the given options.
  external JSPromise<JSAny?> open(SerialOptions options);

  /// Close the port.
  external JSPromise<JSAny?> close();

  /// The readable side of the port (a ReadableStream of Uint8Array).
  external ReadableStream? get readable;

  /// The writable side of the port (a WritableStream of Uint8Array).
  external WritableStream? get writable;

  /// Static metadata about the port (VID, PID, etc.).
  external JSPromise<SerialPortInfo> getInfo();

  /// Forget this port (revokes stored permission).
  external JSPromise<JSAny?> forget();

  /// Set control signals (RTS, DTR, break).
  external JSPromise<JSAny?> setSignals(SerialOutputSignals signals);

  /// Read input control signals (CTS, DSR, RI, DCD).
  external JSPromise<SerialInputSignals> getSignals();
}

// ── SerialOptions ────────────────────────────────────────────────────────────

extension type SerialOptions._(JSObject _) implements JSObject {
  external factory SerialOptions({
    required int baudRate,
    int? dataBits,   // 7 or 8 (default 8)
    int? stopBits,   // 1 or 2 (default 1)
    String? parity,  // 'none' | 'even' | 'odd' (default 'none')
    int? bufferSize, // default 255
    String? flowControl, // 'none' | 'hardware' (default 'none')
  });

  external int get baudRate;
  external int get dataBits;
  external int get stopBits;
  external String get parity;
  external int get bufferSize;
  external String get flowControl;
}

// ── SerialPortInfo ───────────────────────────────────────────────────────────

extension type SerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
  external String? get usbSerialNumber;
}

// ── Control signals ──────────────────────────────────────────────────────────

extension type SerialOutputSignals._(JSObject _) implements JSObject {
  external factory SerialOutputSignals({bool? dataTerminalReady, bool? requestToSend, bool? break_});
  external bool? get dataTerminalReady;
  external bool? get requestToSend;
  // 'break' is a reserved keyword in Dart, exposed as break_ via JS interop name
}

extension type SerialInputSignals._(JSObject _) implements JSObject {
  external bool get clearToSend;
  external bool get dataCarrierDetect;
  external bool get dataSetReady;
  external bool get ringIndicator;
}

// ── ReadableStream / WritableStream (minimal surface needed) ─────────────────

extension type ReadableStream._(JSObject _) implements JSObject {
  external ReadableStreamDefaultReader getReader();
  external JSPromise<JSAny?> cancel([JSAny? reason]);
}

extension type ReadableStreamDefaultReader._(JSObject _) implements JSObject {
  /// Reads the next chunk. Resolves with `{value: Uint8Array|undefined, done: bool}`.
  external JSPromise<ReadableStreamReadResult> read();
  external JSPromise<JSAny?> cancel([JSAny? reason]);
  external void releaseLock();
}

extension type ReadableStreamReadResult._(JSObject _) implements JSObject {
  external JSUint8Array? get value;
  external bool get done;
}

extension type WritableStream._(JSObject _) implements JSObject {
  external WritableStreamDefaultWriter getWriter();
}

extension type WritableStreamDefaultWriter._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array chunk);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> abort([JSAny? reason]);
  external void releaseLock();
  /// Resolves when the writer's internal queue is drained.
  external JSPromise<JSAny?> get ready;
}
