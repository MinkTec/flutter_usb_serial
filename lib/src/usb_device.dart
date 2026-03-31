import 'package:flutter/foundation.dart';

/// Metadata for a connected USB serial device.
///
/// Obtain instances via [FlutterUsbSerial.getDevices].
@immutable
class UsbDevice {
  const UsbDevice({
    required this.deviceId,
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.driverType,
    required this.portCount,
    required this.hasPermission,
    this.manufacturerName,
    this.productName,
    this.serialNumber,
  });

  /// Android-assigned device ID (changes on reconnect).
  final int deviceId;

  /// Android device path, e.g. "/dev/bus/usb/001/002".
  final String deviceName;

  /// USB vendor ID (e.g. 0x0403 for FTDI).
  final int vendorId;

  /// USB product ID (e.g. 0x6001 for FT232R).
  final int productId;

  /// Manufacturer string from the USB descriptor, if available.
  final String? manufacturerName;

  /// Product string from the USB descriptor, if available.
  final String? productName;

  /// Serial number string, if available (may be null on Android 10+ without
  /// the READ_PHONE_STATE permission).
  final String? serialNumber;

  /// Driver type name, e.g. "Ftdi", "Cp21xx", "CdcAcm", "Ch34x", "Prolific".
  final String driverType;

  /// Number of serial ports exposed by this device (usually 1).
  final int portCount;

  /// Whether the app currently holds USB permission for this device.
  final bool hasPermission;

  // ── Convenience getters ──────────────────────────────────────────────────

  /// Vendor ID formatted as uppercase hex, e.g. "0x0403".
  String get vid =>
      '0x${vendorId.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// Product ID formatted as uppercase hex, e.g. "0x6001".
  String get pid =>
      '0x${productId.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  /// Best available display name: [productName] if set, otherwise [deviceName].
  String get displayName =>
      (productName?.isNotEmpty == true) ? productName! : deviceName;

  // ── Serialization ────────────────────────────────────────────────────────

  factory UsbDevice.fromMap(Map<Object?, Object?> map) {
    return UsbDevice(
      deviceId: map['deviceId'] as int,
      deviceName: map['deviceName'] as String,
      vendorId: map['vendorId'] as int,
      productId: map['productId'] as int,
      manufacturerName: map['manufacturerName'] as String?,
      productName: map['productName'] as String?,
      serialNumber: map['serialNumber'] as String?,
      driverType: map['driverType'] as String,
      portCount: map['portCount'] as int,
      hasPermission: map['hasPermission'] as bool,
    );
  }

  /// Returns a copy with [hasPermission] updated.
  UsbDevice withPermission(bool granted) => UsbDevice(
        deviceId: deviceId,
        deviceName: deviceName,
        vendorId: vendorId,
        productId: productId,
        manufacturerName: manufacturerName,
        productName: productName,
        serialNumber: serialNumber,
        driverType: driverType,
        portCount: portCount,
        hasPermission: granted,
      );

  @override
  String toString() =>
      'UsbDevice(id=$deviceId, $displayName, vid=$vid, pid=$pid, '
      'driver=$driverType, ports=$portCount, permission=$hasPermission)';
}
