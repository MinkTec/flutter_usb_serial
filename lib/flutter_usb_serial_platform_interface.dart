import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_usb_serial_method_channel.dart';

/// Platform interface for flutter_usb_serial.
///
/// The plugin is currently Android-only. All functionality is exposed through
/// the static methods on [FlutterUsbSerial] via a direct [MethodChannel].
abstract class FlutterUsbSerialPlatform extends PlatformInterface {
  FlutterUsbSerialPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterUsbSerialPlatform _instance = MethodChannelFlutterUsbSerial();

  static FlutterUsbSerialPlatform get instance => _instance;

  static set instance(FlutterUsbSerialPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }
}
