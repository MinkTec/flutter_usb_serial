/// Web factory — compiled only when dart:js_interop is available.
///
/// Constructs [UsbPortWeb] from a JS SerialPort object.
/// The native factory is a no-op stub on this platform.
library;

import 'package:flutter/services.dart' show PlatformException;

import 'flutter_usb_serial_web.dart';
import 'usb_port.dart';
import 'web_serial_interop.dart';

UsbPort createFromNativePort(Object port) =>
    throw PlatformException(
      code: 'UNSUPPORTED',
      message: 'fromNativePort is not supported on web.',
    );

UsbPort createFromWebPort(Object jsPort) =>
    UsbPortWeb.fromOpenPort(jsPort as SerialPort);
