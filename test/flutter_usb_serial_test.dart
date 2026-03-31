import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

// ── Mock channel handler ───────────────────────────────────────────────────────

typedef _MockHandler = Future<Object?> Function(MethodCall call);

void _setMock(_MockHandler handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_usb_serial'),
    handler,
  );
}

void _clearMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_usb_serial'),
    null,
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Map<Object?, Object?> _rawDevice({
  int deviceId = 1,
  String deviceName = '/dev/bus/usb/001/002',
  int vendorId = 0x0403,
  int productId = 0x6001,
  String? manufacturerName = 'FTDI',
  String? productName = 'FT232R USB UART',
  String? serialNumber = 'ABC123',
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

UsbDevice _device({bool hasPermission = true}) =>
    UsbDevice.fromMap(_rawDevice(hasPermission: hasPermission));

// ── FlutterUsbSerial.getDevices ────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_clearMock);

  group('FlutterUsbSerial.getDevices', () {
    test('returns empty list when channel returns null', () async {
      _setMock((_) async => null);
      final devices = await FlutterUsbSerial.getDevices();
      expect(devices, isEmpty);
    });

    test('returns empty list when channel returns empty list', () async {
      _setMock((_) async => <Object?>[]);
      final devices = await FlutterUsbSerial.getDevices();
      expect(devices, isEmpty);
    });

    test('returns one device', () async {
      _setMock((_) async => [_rawDevice()]);
      final devices = await FlutterUsbSerial.getDevices();
      expect(devices, hasLength(1));
      expect(devices.first.vendorId, 0x0403);
      expect(devices.first.driverType, 'Ftdi');
    });

    test('returns multiple devices', () async {
      _setMock((_) async => [
            _rawDevice(deviceId: 1, vendorId: 0x0403),
            _rawDevice(deviceId: 2, vendorId: 0x10C4, driverType: 'Cp21xx'),
          ]);
      final devices = await FlutterUsbSerial.getDevices();
      expect(devices, hasLength(2));
      expect(devices[0].deviceId, 1);
      expect(devices[1].vendorId, 0x10C4);
    });

    test('skips non-map entries', () async {
      _setMock((_) async => [_rawDevice(), 'bad_entry', null]);
      final devices = await FlutterUsbSerial.getDevices();
      expect(devices, hasLength(1));
    });

    test('calls getDevices method on channel', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return <Object?>[];
      });
      await FlutterUsbSerial.getDevices();
      expect(captured?.method, 'getDevices');
    });
  });

  // ── FlutterUsbSerial.hasPermission ─────────────────────────────────────────

  group('FlutterUsbSerial.hasPermission', () {
    test('returns true when channel returns true', () async {
      _setMock((_) async => true);
      expect(await FlutterUsbSerial.hasPermission(_device()), isTrue);
    });

    test('returns false when channel returns false', () async {
      _setMock((_) async => false);
      expect(await FlutterUsbSerial.hasPermission(_device()), isFalse);
    });

    test('returns false when channel returns null', () async {
      _setMock((_) async => null);
      expect(await FlutterUsbSerial.hasPermission(_device()), isFalse);
    });

    test('sends correct deviceId', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return true;
      });
      final d = UsbDevice.fromMap(_rawDevice(deviceId: 99));
      await FlutterUsbSerial.hasPermission(d);
      expect(captured?.method, 'hasPermission');
      expect(captured?.arguments['deviceId'], 99);
    });
  });

  // ── FlutterUsbSerial.requestPermission ─────────────────────────────────────

  group('FlutterUsbSerial.requestPermission', () {
    test('returns true when granted', () async {
      _setMock((_) async => true);
      expect(await FlutterUsbSerial.requestPermission(_device()), isTrue);
    });

    test('returns false when denied', () async {
      _setMock((_) async => false);
      expect(await FlutterUsbSerial.requestPermission(_device()), isFalse);
    });

    test('returns false when channel returns null', () async {
      _setMock((_) async => null);
      expect(await FlutterUsbSerial.requestPermission(_device()), isFalse);
    });

    test('sends correct method and deviceId', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return true;
      });
      final d = UsbDevice.fromMap(_rawDevice(deviceId: 7));
      await FlutterUsbSerial.requestPermission(d);
      expect(captured?.method, 'requestPermission');
      expect(captured?.arguments['deviceId'], 7);
    });
  });

  // ── FlutterUsbSerial.openPort ──────────────────────────────────────────────

  group('FlutterUsbSerial.openPort', () {
    test('returns UsbPort on success', () async {
      _setMock((_) async => 0);
      final port = await FlutterUsbSerial.openPort(_device());
      expect(port, isA<UsbPort>());
    });

    test('throws PlatformException when channel returns null portId', () async {
      _setMock((_) async => null);
      expect(
        () => FlutterUsbSerial.openPort(_device()),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'OPEN_FAILED')),
      );
    });

    test('sends correct arguments with defaults', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return 0;
      });
      final d = UsbDevice.fromMap(_rawDevice(deviceId: 5));
      await FlutterUsbSerial.openPort(d);
      expect(captured?.method, 'openPort');
      final args = captured?.arguments as Map;
      expect(args['deviceId'], 5);
      expect(args['portNumber'], 0);
      expect(args['baudRate'], 9600);
      expect(args['dataBits'], UsbDataBits.bits8);
      expect(args['stopBits'], UsbStopBits.one);
      expect(args['parity'], UsbParity.none);
    });

    test('sends custom parameters', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return 1;
      });
      await FlutterUsbSerial.openPort(
        _device(),
        portNumber: 2,
        baudRate: 115200,
        dataBits: UsbDataBits.bits7,
        stopBits: UsbStopBits.two,
        parity: UsbParity.even,
      );
      final args = captured?.arguments as Map;
      expect(args['portNumber'], 2);
      expect(args['baudRate'], 115200);
      expect(args['dataBits'], UsbDataBits.bits7);
      expect(args['stopBits'], UsbStopBits.two);
      expect(args['parity'], UsbParity.even);
    });

    test('propagates PlatformException from channel', () async {
      _setMock((_) async =>
          throw PlatformException(code: 'NO_PERMISSION', message: 'denied'));
      expect(
        () => FlutterUsbSerial.openPort(_device()),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'NO_PERMISSION')),
      );
    });
  });

  // ── UsbPort method calls ───────────────────────────────────────────────────

  group('UsbPort.setParameters', () {
    test('sends all parameters to channel', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        if (call.method == 'openPort') return 42;
        return null;
      });
      final port = UsbPort.fromPortId(42);
      await port.setParameters(
        115200,
        dataBits: UsbDataBits.bits7,
        stopBits: UsbStopBits.two,
        parity: UsbParity.odd,
      );
      expect(captured?.method, 'setParameters');
      final args = captured?.arguments as Map;
      expect(args['portId'], 42);
      expect(args['baudRate'], 115200);
      expect(args['dataBits'], UsbDataBits.bits7);
      expect(args['stopBits'], UsbStopBits.two);
      expect(args['parity'], UsbParity.odd);
    });
  });

  group('UsbPort.write', () {
    test('sends data bytes to channel', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      final port = UsbPort.fromPortId(1);
      final data = Uint8List.fromList([0x41, 0x42, 0x0D, 0x0A]);
      await port.write(data);
      expect(captured?.method, 'write');
      expect(captured?.arguments['portId'], 1);
      expect(captured?.arguments['data'], data);
    });
  });

  group('UsbPort.close', () {
    test('sends closePort with correct portId', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      final port = UsbPort.fromPortId(7);
      await port.close();
      expect(captured?.method, 'closePort');
      expect(captured?.arguments['portId'], 7);
    });
  });

  group('UsbPort.isOpen', () {
    test('returns true when channel returns true', () async {
      _setMock((_) async => true);
      final port = UsbPort.fromPortId(0);
      expect(await port.isOpen(), isTrue);
    });

    test('returns false when channel returns false', () async {
      _setMock((_) async => false);
      final port = UsbPort.fromPortId(0);
      expect(await port.isOpen(), isFalse);
    });

    test('returns false when channel returns null', () async {
      _setMock((_) async => null);
      final port = UsbPort.fromPortId(0);
      expect(await port.isOpen(), isFalse);
    });
  });

  group('UsbPort.setRTS / setDTR', () {
    test('setRTS sends value=true', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(3).setRTS(true);
      expect(captured?.method, 'setRTS');
      expect(captured?.arguments['value'], isTrue);
      expect(captured?.arguments['portId'], 3);
    });

    test('setRTS sends value=false', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(3).setRTS(false);
      expect(captured?.arguments['value'], isFalse);
    });

    test('setDTR sends value=true', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(4).setDTR(true);
      expect(captured?.method, 'setDTR');
      expect(captured?.arguments['portId'], 4);
      expect(captured?.arguments['value'], isTrue);
    });
  });

  group('UsbPort.getControlLines', () {
    test('returns parsed map', () async {
      _setMock((_) async => {
            'RTS': true,
            'CTS': false,
            'DTR': true,
            'DSR': false,
            'CD': false,
            'RI': false,
          });
      final lines = await UsbPort.fromPortId(0).getControlLines();
      expect(lines['RTS'], isTrue);
      expect(lines['CTS'], isFalse);
      expect(lines['DTR'], isTrue);
    });

    test('returns empty map when channel returns null', () async {
      _setMock((_) async => null);
      final lines = await UsbPort.fromPortId(0).getControlLines();
      expect(lines, isEmpty);
    });
  });

  group('UsbPort.getSupportedControlLines', () {
    test('returns list of line names', () async {
      _setMock((_) async => ['RTS', 'DTR', 'CTS']);
      final lines = await UsbPort.fromPortId(0).getSupportedControlLines();
      expect(lines, containsAll(['RTS', 'DTR', 'CTS']));
    });

    test('returns empty list when channel returns null', () async {
      _setMock((_) async => null);
      final lines = await UsbPort.fromPortId(0).getSupportedControlLines();
      expect(lines, isEmpty);
    });
  });

  group('UsbPort.purgeHwBuffers', () {
    test('sends both flags as true by default', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(5).purgeHwBuffers();
      expect(captured?.method, 'purgeHwBuffers');
      expect(captured?.arguments['purgeWrite'], isTrue);
      expect(captured?.arguments['purgeRead'], isTrue);
    });

    test('can set flags independently', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(5)
          .purgeHwBuffers(purgeWriteBuffers: false, purgeReadBuffers: true);
      expect(captured?.arguments['purgeWrite'], isFalse);
      expect(captured?.arguments['purgeRead'], isTrue);
    });
  });

  group('UsbPort.setBreak', () {
    test('sends value=true', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(6).setBreak(true);
      expect(captured?.method, 'setBreak');
      expect(captured?.arguments['value'], isTrue);
      expect(captured?.arguments['portId'], 6);
    });

    test('sends value=false', () async {
      MethodCall? captured;
      _setMock((call) async {
        captured = call;
        return null;
      });
      await UsbPort.fromPortId(6).setBreak(false);
      expect(captured?.arguments['value'], isFalse);
    });
  });

  group('UsbPort.setFlowControl', () {
    test('sends androidName for each variant', () async {
      for (final fc in UsbFlowControl.values) {
        MethodCall? captured;
        _setMock((call) async {
          captured = call;
          return null;
        });
        await UsbPort.fromPortId(0).setFlowControl(fc);
        expect(captured?.method, 'setFlowControl');
        expect(captured?.arguments['mode'], fc.androidName,
            reason: 'Variant ${fc.name} should send androidName');
      }
    });
  });
}
