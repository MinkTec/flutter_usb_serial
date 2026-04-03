import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

Map<Object?, Object?> _deviceMap({
  int deviceId = 1,
  String deviceName = '/dev/bus/usb/001/002',
  int vendorId = 0x0403,
  int productId = 0x6001,
  String? manufacturerName = 'FTDI',
  String? productName = 'FT232R USB UART',
  String? serialNumber = 'A12345',
  String driverType = 'Ftdi',
  int portCount = 1,
  bool hasPermission = true,
}) =>
    {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'vendorId': vendorId,
      'productId': productId,
      'manufacturerName': manufacturerName,
      'productName': productName,
      'serialNumber': serialNumber,
      'driverType': driverType,
      'portCount': portCount,
      'hasPermission': hasPermission,
    };

// ── UsbDevice.fromMap ──────────────────────────────────────────────────────────

void main() {
  group('UsbDevice.fromMap', () {
    test('parses all fields correctly', () {
      final d = UsbDevice.fromMap(_deviceMap());

      expect(d.deviceId, 1);
      expect(d.deviceName, '/dev/bus/usb/001/002');
      expect(d.vendorId, 0x0403);
      expect(d.productId, 0x6001);
      expect(d.manufacturerName, 'FTDI');
      expect(d.productName, 'FT232R USB UART');
      expect(d.serialNumber, 'A12345');
      expect(d.driverType, 'Ftdi');
      expect(d.portCount, 1);
      expect(d.hasPermission, isTrue);
    });

    test('accepts null optional fields', () {
      final d = UsbDevice.fromMap(_deviceMap(
        manufacturerName: null,
        productName: null,
        serialNumber: null,
      ));

      expect(d.manufacturerName, isNull);
      expect(d.productName, isNull);
      expect(d.serialNumber, isNull);
    });

    test('parses hasPermission=false', () {
      final d = UsbDevice.fromMap(_deviceMap(hasPermission: false));
      expect(d.hasPermission, isFalse);
    });

    test('parses multi-port device', () {
      final d = UsbDevice.fromMap(_deviceMap(portCount: 4));
      expect(d.portCount, 4);
    });
  });

  // ── vid / pid getters ──────────────────────────────────────────────────────

  group('UsbDevice.vid / pid', () {
    test('formats FTDI FT232R correctly', () {
      final d =
          UsbDevice.fromMap(_deviceMap(vendorId: 0x0403, productId: 0x6001));
      expect(d.vid, '0x0403');
      expect(d.pid, '0x6001');
    });

    test('zero IDs produce 0x0000', () {
      final d = UsbDevice.fromMap(_deviceMap(vendorId: 0, productId: 0));
      expect(d.vid, '0x0000');
      expect(d.pid, '0x0000');
    });

    test('max 16-bit value produces 0xFFFF', () {
      final d =
          UsbDevice.fromMap(_deviceMap(vendorId: 0xFFFF, productId: 0xFFFF));
      expect(d.vid, '0xFFFF');
      expect(d.pid, '0xFFFF');
    });

    test('uses uppercase hex', () {
      final d =
          UsbDevice.fromMap(_deviceMap(vendorId: 0xabcd, productId: 0xef01));
      expect(d.vid, '0xABCD');
      expect(d.pid, '0xEF01');
    });

    test('pads to 4 digits', () {
      final d = UsbDevice.fromMap(_deviceMap(vendorId: 0x1, productId: 0xFF));
      expect(d.vid, '0x0001');
      expect(d.pid, '0x00FF');
    });
  });

  // ── displayName ────────────────────────────────────────────────────────────

  group('UsbDevice.displayName', () {
    test('returns productName when set', () {
      final d = UsbDevice.fromMap(_deviceMap(productName: 'My Device'));
      expect(d.displayName, 'My Device');
    });

    test('falls back to deviceName when productName is null', () {
      final d = UsbDevice.fromMap(
          _deviceMap(productName: null, deviceName: '/dev/bus/usb/001/003'));
      expect(d.displayName, '/dev/bus/usb/001/003');
    });

    test('falls back to deviceName when productName is empty string', () {
      final d = UsbDevice.fromMap(
          _deviceMap(productName: '', deviceName: '/dev/bus/usb/001/004'));
      expect(d.displayName, '/dev/bus/usb/001/004');
    });
  });

  // ── withPermission ─────────────────────────────────────────────────────────

  group('UsbDevice.withPermission', () {
    test('creates copy with hasPermission=true', () {
      final original = UsbDevice.fromMap(_deviceMap(hasPermission: false));
      final copy = original.withPermission(true);

      expect(copy.hasPermission, isTrue);
      expect(copy.deviceId, original.deviceId);
      expect(copy.deviceName, original.deviceName);
      expect(copy.vendorId, original.vendorId);
      expect(copy.productId, original.productId);
      expect(copy.manufacturerName, original.manufacturerName);
      expect(copy.productName, original.productName);
      expect(copy.serialNumber, original.serialNumber);
      expect(copy.driverType, original.driverType);
      expect(copy.portCount, original.portCount);
    });

    test('creates copy with hasPermission=false', () {
      final original = UsbDevice.fromMap(_deviceMap(hasPermission: true));
      final copy = original.withPermission(false);
      expect(copy.hasPermission, isFalse);
    });

    test('does not mutate original', () {
      final original = UsbDevice.fromMap(_deviceMap(hasPermission: false));
      original.withPermission(true);
      expect(original.hasPermission, isFalse);
    });
  });

  // ── toString ───────────────────────────────────────────────────────────────

  group('UsbDevice.toString', () {
    test('contains key identifying fields', () {
      final d = UsbDevice.fromMap(_deviceMap(
        deviceId: 42,
        vendorId: 0x0403,
        productId: 0x6001,
        driverType: 'Ftdi',
        portCount: 2,
        hasPermission: true,
      ));
      final s = d.toString();
      expect(s, contains('42'));
      expect(s, contains('0x0403'));
      expect(s, contains('0x6001'));
      expect(s, contains('Ftdi'));
      expect(s, contains('2'));
      expect(s, contains('true'));
    });
  });
}
