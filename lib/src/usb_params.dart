/// USB serial parameter constants and enums.
library;

/// Data bits constants for [UsbPort.setParameters].
abstract final class UsbDataBits {
  static const int bits5 = 5;
  static const int bits6 = 6;
  static const int bits7 = 7;
  static const int bits8 = 8;
}

/// Stop bits constants for [UsbPort.setParameters].
abstract final class UsbStopBits {
  static const int one = 1;

  /// 1.5 stop bits (not supported by all drivers).
  static const int onePointFive = 3;
  static const int two = 2;
}

/// Parity constants for [UsbPort.setParameters].
abstract final class UsbParity {
  static const int none = 0;
  static const int odd = 1;
  static const int even = 2;

  /// Mark parity (not supported by all drivers).
  static const int mark = 3;

  /// Space parity (not supported by all drivers).
  static const int space = 4;
}

/// Flow control modes for [UsbPort.setFlowControl].
enum UsbFlowControl {
  none('NONE'),
  rtsCts('RTS_CTS'),
  dtrDsr('DTR_DSR'),
  xonXoff('XON_XOFF'),
  xonXoffInline('XON_XOFF_INLINE');

  const UsbFlowControl(this._androidName);
  final String _androidName;

  /// The string identifier sent to the Android plugin.
  String get androidName => _androidName;
}

/// Hardware control line identifiers.
enum UsbControlLine { rts, cts, dtr, dsr, cd, ri }
