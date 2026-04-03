import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

void main() {
  // ── UsbDataBits ────────────────────────────────────────────────────────────

  group('UsbDataBits', () {
    test('bits5 == 5', () => expect(UsbDataBits.bits5, 5));
    test('bits6 == 6', () => expect(UsbDataBits.bits6, 6));
    test('bits7 == 7', () => expect(UsbDataBits.bits7, 7));
    test('bits8 == 8', () => expect(UsbDataBits.bits8, 8));
  });

  // ── UsbStopBits ────────────────────────────────────────────────────────────

  group('UsbStopBits', () {
    test('one == 1', () => expect(UsbStopBits.one, 1));
    test('onePointFive == 3', () => expect(UsbStopBits.onePointFive, 3));
    test('two == 2', () => expect(UsbStopBits.two, 2));
  });

  // ── UsbParity ──────────────────────────────────────────────────────────────

  group('UsbParity', () {
    test('none == 0', () => expect(UsbParity.none, 0));
    test('odd == 1', () => expect(UsbParity.odd, 1));
    test('even == 2', () => expect(UsbParity.even, 2));
    test('mark == 3', () => expect(UsbParity.mark, 3));
    test('space == 4', () => expect(UsbParity.space, 4));
  });

  // ── UsbFlowControl ─────────────────────────────────────────────────────────

  group('UsbFlowControl.androidName', () {
    test('none', () => expect(UsbFlowControl.none.androidName, 'NONE'));
    test('rtsCts', () => expect(UsbFlowControl.rtsCts.androidName, 'RTS_CTS'));
    test('dtrDsr', () => expect(UsbFlowControl.dtrDsr.androidName, 'DTR_DSR'));
    test('xonXoff',
        () => expect(UsbFlowControl.xonXoff.androidName, 'XON_XOFF'));
    test(
        'xonXoffInline',
        () => expect(
            UsbFlowControl.xonXoffInline.androidName, 'XON_XOFF_INLINE'));
  });

  group('UsbFlowControl values', () {
    test('has exactly 5 variants',
        () => expect(UsbFlowControl.values.length, 5));

    test('all variants have non-empty androidName', () {
      for (final fc in UsbFlowControl.values) {
        expect(fc.androidName, isNotEmpty,
            reason: '${fc.name}.androidName must not be empty');
      }
    });
  });

  // ── UsbControlLine ─────────────────────────────────────────────────────────

  group('UsbControlLine', () {
    test('has exactly 6 variants',
        () => expect(UsbControlLine.values.length, 6));

    test('contains rts, cts, dtr, dsr, cd, ri', () {
      final names = UsbControlLine.values.map((e) => e.name).toSet();
      expect(names, containsAll(['rts', 'cts', 'dtr', 'dsr', 'cd', 'ri']));
    });
  });
}
