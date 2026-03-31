import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

// ── Data model ─────────────────────────────────────────────────────────────────

class _TerminalEntry {
  _TerminalEntry({required this.isRx, required this.data})
      : timestamp = DateTime.now();

  final DateTime timestamp;
  final bool isRx;
  final Uint8List data;
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.device,
    required this.portNumber,
  });

  final UsbDevice device;
  final int portNumber;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  // ── Connection ──────────────────────────────────────────────────────────────
  UsbPort? _port;
  bool _isConnected = false;
  bool _isConnecting = false;
  StreamSubscription<Uint8List>? _subscription;

  // ── Terminal output ─────────────────────────────────────────────────────────
  final List<_TerminalEntry> _entries = [];
  bool _displayHex = false;
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();

  // ── Send field ──────────────────────────────────────────────────────────────
  bool _hexInputMode = false;
  String _eolMode = 'LF'; // 'none' | 'CR' | 'LF' | 'CRLF'
  final TextEditingController _sendController = TextEditingController();
  bool _isSending = false;

  // ── Serial parameters ───────────────────────────────────────────────────────
  int _baudRate = 9600;
  int _dataBits = UsbDataBits.bits8;
  int _stopBits = UsbStopBits.one;
  int _parity = UsbParity.none;

  // ── Control lines ───────────────────────────────────────────────────────────
  bool _rtsState = false;
  bool _dtrState = false;
  Map<String, bool> _controlLines = {};
  List<String> _supportedControlLines = [];
  Timer? _controlLineTimer;

  // ── Constants ───────────────────────────────────────────────────────────────
  static const _kBaudRates = [
    300, 600, 1200, 2400, 4800, 9600, 19200, 38400, //
    57600, 115200, 230400, 460800, 921600, 1500000, 2000000, 3000000,
  ];
  static const _kBgColor = Color(0xFF0D1117);
  static const _kRxColor = Color(0xFF58A6FF); // blue
  static const _kTxColor = Color(0xFF3FB950); // green
  static const _kMonoStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.5,
  );

  @override
  void dispose() {
    _controlLineTimer?.cancel();
    _subscription?.cancel();
    _port?.close();
    _scrollController.dispose();
    _sendController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _toHex(Uint8List data) => data
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  String _toAscii(Uint8List data) => String.fromCharCodes(
        data.map((b) => (b >= 0x20 && b < 0x7F) ? b : 0x2E), // '.'
      );

  String _formatEntry(_TerminalEntry e) =>
      _displayHex ? _toHex(e.data) : _toAscii(e.data);

  Uint8List? _parseHexInput(String s) {
    final clean = s.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return Uint8List(0);
    if (clean.length.isOdd) return null;
    try {
      final bytes = Uint8List(clean.length ~/ 2);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Uint8List? _buildSendPayload() {
    final text = _sendController.text;
    Uint8List base;
    if (_hexInputMode) {
      final parsed = _parseHexInput(text);
      if (parsed == null) return null;
      base = parsed;
    } else {
      base = Uint8List.fromList(text.codeUnits);
    }

    List<int> suffix;
    switch (_eolMode) {
      case 'CR':
        suffix = [0x0D];
      case 'LF':
        suffix = [0x0A];
      case 'CRLF':
        suffix = [0x0D, 0x0A];
      default:
        suffix = [];
    }

    if (suffix.isEmpty) return base;
    return Uint8List.fromList([...base, ...suffix]);
  }

  void _addEntry({required bool isRx, required Uint8List data}) {
    setState(() => _entries.add(_TerminalEntry(isRx: isRx, data: data)));
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // ── Connection management ───────────────────────────────────────────────────

  Future<void> _connect() async {
    setState(() => _isConnecting = true);
    try {
      final port = await FlutterUsbSerial.openPort(
        widget.device,
        portNumber: widget.portNumber,
      );
      await port.setParameters(
        _baudRate,
        dataBits: _dataBits,
        stopBits: _stopBits,
        parity: _parity,
      );

      final supported = await port.getSupportedControlLines();

      _subscription = port.inputStream.listen(
        (data) => _addEntry(isRx: true, data: data),
        onError: (Object e) {
          _addEntry(
            isRx: true,
            data: Uint8List.fromList('[read error: $e]'.codeUnits),
          );
          _disconnect();
        },
        onDone: _disconnect,
      );

      setState(() {
        _port = port;
        _isConnected = true;
        _supportedControlLines = supported;
      });

      // Start control line polling
      _controlLineTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _pollControlLines(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connect failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    _controlLineTimer?.cancel();
    _controlLineTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _port?.close();
    if (mounted) {
      setState(() {
        _port = null;
        _isConnected = false;
        _controlLines = {};
        _supportedControlLines = [];
      });
    }
  }

  // ── Send ────────────────────────────────────────────────────────────────────

  Future<void> _sendData() async {
    final port = _port;
    if (port == null || _isSending) return;

    final payload = _buildSendPayload();
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid hex input'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (payload.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await port.write(payload);
      _addEntry(isRx: false, data: payload);
      _sendController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Write error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Control lines ───────────────────────────────────────────────────────────

  Future<void> _pollControlLines() async {
    final port = _port;
    if (port == null) return;
    try {
      final lines = await port.getControlLines();
      if (mounted) setState(() => _controlLines = lines);
    } catch (_) {
      // Ignore — driver may not support all lines
    }
  }

  Future<void> _setRTS(bool value) async {
    try {
      await _port?.setRTS(value);
      setState(() => _rtsState = value);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RTS error: $e')),
        );
    }
  }

  Future<void> _setDTR(bool value) async {
    try {
      await _port?.setDTR(value);
      setState(() => _dtrState = value);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DTR error: $e')),
        );
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final portLabel =
        '${widget.device.displayName}  •  Port ${widget.portNumber}';

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: Text(
          portLabel,
          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: _isConnected ? _disconnect : _connect,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _isConnected ? Colors.red.shade800 : cs.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Settings row (hidden when connected) ──────────────────────────
          _SettingsRow(
            visible: !_isConnected,
            baudRate: _baudRate,
            dataBits: _dataBits,
            stopBits: _stopBits,
            parity: _parity,
            baudRates: _kBaudRates,
            onBaudRate: (v) => setState(() => _baudRate = v),
            onDataBits: (v) => setState(() => _dataBits = v),
            onStopBits: (v) => setState(() => _stopBits = v),
            onParity: (v) => setState(() => _parity = v),
          ),

          // ── Terminal output area ───────────────────────────────────────────
          Expanded(
            child: Container(
              color: _kBgColor,
              child: _entries.isEmpty
                  ? Center(
                      child: Text(
                        _isConnected ? 'Waiting for data...' : 'Not connected',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) => _TerminalLine(
                        entry: _entries[i],
                        text: _formatEntry(_entries[i]),
                        rxColor: _kRxColor,
                        txColor: _kTxColor,
                        monoStyle: _kMonoStyle,
                      ),
                    ),
            ),
          ),

          // ── Output toolbar ─────────────────────────────────────────────────
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                // Display mode toggle
                _SmallToggle(
                  labels: const ['ASCII', 'HEX'],
                  selected: _displayHex ? 1 : 0,
                  onChanged: (i) => setState(() => _displayHex = i == 1),
                ),
                const Spacer(),
                // Auto-scroll
                IconButton(
                  icon: Icon(
                    _autoScroll
                        ? Icons.vertical_align_bottom
                        : Icons.vertical_align_center,
                    size: 18,
                  ),
                  tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
                  color: _autoScroll ? Colors.blue.shade300 : Colors.white38,
                  onPressed: () => setState(() => _autoScroll = !_autoScroll),
                ),
                // Clear
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  tooltip: 'Clear terminal',
                  color: Colors.white38,
                  onPressed: () => setState(() => _entries.clear()),
                ),
              ],
            ),
          ),

          // ── Control lines row (visible when connected) ─────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isConnected
                ? _ControlLinesRow(
                    rts: _rtsState,
                    dtr: _dtrState,
                    lines: _controlLines,
                    supported: _supportedControlLines,
                    onRts: _setRTS,
                    onDtr: _setDTR,
                  )
                : const SizedBox.shrink(),
          ),

          // ── Input area ─────────────────────────────────────────────────────
          _InputSection(
            controller: _sendController,
            hexMode: _hexInputMode,
            eolMode: _eolMode,
            isSending: _isSending,
            isConnected: _isConnected,
            onHexMode: (v) => setState(() => _hexInputMode = v),
            onEolMode: (v) => setState(() => _eolMode = v),
            onSend: _sendData,
          ),
        ],
      ),
    );
  }
}

// ── Settings row ───────────────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.visible,
    required this.baudRate,
    required this.dataBits,
    required this.stopBits,
    required this.parity,
    required this.baudRates,
    required this.onBaudRate,
    required this.onDataBits,
    required this.onStopBits,
    required this.onParity,
  });

  final bool visible;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final int parity;
  final List<int> baudRates;
  final ValueChanged<int> onBaudRate;
  final ValueChanged<int> onDataBits;
  final ValueChanged<int> onStopBits;
  final ValueChanged<int> onParity;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: visible
          ? Container(
              color: const Color(0xFF161B22),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ParamDropdown<int>(
                      label: 'Baud',
                      value: baudRate,
                      items: baudRates
                          .map((b) => DropdownMenuItem(
                              value: b, child: Text(b.toString())))
                          .toList(),
                      onChanged: (v) => onBaudRate(v!),
                    ),
                    const SizedBox(width: 8),
                    _ParamDropdown<int>(
                      label: 'Data',
                      value: dataBits,
                      items: [5, 6, 7, 8]
                          .map((b) => DropdownMenuItem(
                              value: b, child: Text('$b bits')))
                          .toList(),
                      onChanged: (v) => onDataBits(v!),
                    ),
                    const SizedBox(width: 8),
                    _ParamDropdown<int>(
                      label: 'Stop',
                      value: stopBits,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1')),
                        DropdownMenuItem(value: 3, child: Text('1.5')),
                        DropdownMenuItem(value: 2, child: Text('2')),
                      ],
                      onChanged: (v) => onStopBits(v!),
                    ),
                    const SizedBox(width: 8),
                    _ParamDropdown<int>(
                      label: 'Parity',
                      value: parity,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('None')),
                        DropdownMenuItem(value: 1, child: Text('Odd')),
                        DropdownMenuItem(value: 2, child: Text('Even')),
                        DropdownMenuItem(value: 3, child: Text('Mark')),
                        DropdownMenuItem(value: 4, child: Text('Space')),
                      ],
                      onChanged: (v) => onParity(v!),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _ParamDropdown<T> extends StatelessWidget {
  const _ParamDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
              color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
        ),
        DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          dropdownColor: const Color(0xFF1C2128),
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          underline: Container(height: 1, color: Colors.white24),
        ),
      ],
    );
  }
}

// ── Terminal line ──────────────────────────────────────────────────────────────

class _TerminalLine extends StatelessWidget {
  const _TerminalLine({
    required this.entry,
    required this.text,
    required this.rxColor,
    required this.txColor,
    required this.monoStyle,
  });

  final _TerminalEntry entry;
  final String text;
  final Color rxColor;
  final Color txColor;
  final TextStyle monoStyle;

  @override
  Widget build(BuildContext context) {
    final color = entry.isRx ? rxColor : txColor;
    final prefix = entry.isRx ? '← RX' : '→ TX';
    final ts = entry.timestamp;
    final timeStr =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}.${ts.millisecond.toString().padLeft(3, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: monoStyle,
          children: [
            TextSpan(
              text: '[$timeStr] $prefix  ',
              style: monoStyle.copyWith(color: color.withOpacity(0.65)),
            ),
            TextSpan(
              text: text,
              style: monoStyle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Control lines row ──────────────────────────────────────────────────────────

class _ControlLinesRow extends StatelessWidget {
  const _ControlLinesRow({
    required this.rts,
    required this.dtr,
    required this.lines,
    required this.supported,
    required this.onRts,
    required this.onDtr,
  });

  final bool rts;
  final bool dtr;
  final Map<String, bool> lines;
  final List<String> supported;
  final ValueChanged<bool> onRts;
  final ValueChanged<bool> onDtr;

  bool _isSupported(String name) =>
      supported.isEmpty || supported.contains(name);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // RTS toggle
            if (_isSupported('RTS')) ...[
              _ControlToggle(
                label: 'RTS',
                value: rts,
                onChanged: onRts,
              ),
              const SizedBox(width: 6),
            ],
            // DTR toggle
            if (_isSupported('DTR')) ...[
              _ControlToggle(
                label: 'DTR',
                value: dtr,
                onChanged: onDtr,
              ),
              const SizedBox(width: 6),
            ],
            // Read-only status chips
            for (final name in ['CTS', 'DSR', 'CD', 'RI'])
              if (_isSupported(name)) ...[
                _StatusChip(
                  label: name,
                  active: lines[name] ?? false,
                ),
                const SizedBox(width: 6),
              ],
          ],
        ),
      ),
    );
  }
}

class _ControlToggle extends StatelessWidget {
  const _ControlToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = value ? Colors.green.shade400 : Colors.white38;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: value
              ? Colors.green.withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.toggle_on : Icons.toggle_off,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.blue.shade300 : Colors.white24;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? Colors.blue.withOpacity(0.1)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: color,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ── Input section ──────────────────────────────────────────────────────────────

class _InputSection extends StatelessWidget {
  const _InputSection({
    required this.controller,
    required this.hexMode,
    required this.eolMode,
    required this.isSending,
    required this.isConnected,
    required this.onHexMode,
    required this.onEolMode,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool hexMode;
  final String eolMode;
  final bool isSending;
  final bool isConnected;
  final ValueChanged<bool> onHexMode;
  final ValueChanged<String> onEolMode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D0D),
      padding: EdgeInsets.only(
        left: 10,
        right: 10,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode row
          Row(
            children: [
              // EOL dropdown
              DropdownButton<String>(
                value: eolMode,
                isDense: true,
                dropdownColor: const Color(0xFF1C2128),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace'),
                underline: Container(height: 1, color: Colors.white24),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No EOL')),
                  DropdownMenuItem(value: 'CR', child: Text('CR')),
                  DropdownMenuItem(value: 'LF', child: Text('LF')),
                  DropdownMenuItem(value: 'CRLF', child: Text('CR+LF')),
                ],
                onChanged: (v) => onEolMode(v!),
              ),
              const SizedBox(width: 10),
              // Input mode toggle chip
              _SmallToggle(
                labels: const ['ASCII', 'HEX'],
                selected: hexMode ? 1 : 0,
                onChanged: (i) => onHexMode(i == 1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Text field + send button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: isConnected,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white),
                  decoration: InputDecoration(
                    hintText:
                        hexMode ? 'hex bytes (e.g. 41 42 0D)' : 'Enter text...',
                    hintStyle: const TextStyle(
                        color: Colors.white24, fontFamily: 'monospace'),
                    filled: true,
                    fillColor: const Color(0xFF1C2128),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Color(0xFF58A6FF), width: 1.5),
                    ),
                  ),
                  onSubmitted: isConnected ? (_) => onSend() : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (isConnected && !isSending) ? onSend : null,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small toggle buttons ───────────────────────────────────────────────────────

class _SmallToggle extends StatelessWidget {
  const _SmallToggle({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(labels.length, (i) {
        final isSelected = i == selected;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF58A6FF).withOpacity(0.2)
                  : Colors.white.withOpacity(0.04),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF58A6FF).withOpacity(0.7)
                    : Colors.white12,
              ),
              borderRadius: BorderRadius.horizontal(
                left: i == 0 ? const Radius.circular(6) : Radius.zero,
                right: i == labels.length - 1
                    ? const Radius.circular(6)
                    : Radius.zero,
              ),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: isSelected ? const Color(0xFF58A6FF) : Colors.white38,
              ),
            ),
          ),
        );
      }),
    );
  }
}
