import 'flutter_usb_serial_platform_interface.dart';

/// Method-channel implementation of [FlutterUsbSerialPlatform].
///
/// The actual plugin API is on [FlutterUsbSerial] (static methods).
/// This class exists only to satisfy the platform interface registry pattern.
class MethodChannelFlutterUsbSerial extends FlutterUsbSerialPlatform {}
