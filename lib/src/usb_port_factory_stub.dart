/// Stub factory — used when neither dart:ffi nor dart:js_interop is available.
///
/// All methods throw [UnsupportedError] at runtime.
library;

import 'usb_port.dart';

UsbPort createFromNativePort(Object port) =>
    throw UnsupportedError('fromNativePort is not supported on this platform.');

UsbPort createFromWebPort(Object jsPort) =>
    throw UnsupportedError('fromWebPort is not supported on this platform.');
