import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_usb_serial/flutter_usb_serial.dart';

import 'terminal_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<UsbDevice> _devices = [];
  bool _loading = false;
  String? _error;

  /// On web, Web Serial is only available in Chrome/Edge. Show a banner if not.
  bool get _webSerialUnsupported =>
      kIsWeb && !webSerialSupported;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (_webSerialUnsupported) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var devices = await FlutterUsbSerial.getDevices();
      // On web, always append the "connect new device" sentinel at the end
      // so the user can pick a new port even if they already have some.
      if (kIsWeb) {
        devices = [...devices, FlutterUsbSerialWeb.newDeviceSentinel];
      }
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onDeviceTapped(UsbDevice device) async {
    UsbDevice d = device;

    // Web Serial: the picker sentinel opens the browser picker inside openPort.
    // Skip the permission / port-selection logic for the sentinel.
    final isSentinel =
        kIsWeb && device.deviceId == FlutterUsbSerialWeb.kPickerSentinelId;

    if (!isSentinel && !d.hasPermission) {
      final granted = await _requestPermission(d);
      if (!granted) return;
      // Refresh device list to get updated permission state
      final refreshed = await FlutterUsbSerial.getDevices();
      if (!mounted) return;
      d = refreshed.firstWhere(
        (dev) => dev.deviceId == device.deviceId,
        orElse: () => device.withPermission(true),
      );
    }

    // Port selection for multi-port devices (not applicable on web).
    int portNumber = 0;
    if (!kIsWeb && d.portCount > 1) {
      final selected = await _selectPort(d);
      if (selected == null) return;
      portNumber = selected;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(device: d, portNumber: portNumber),
      ),
    );
  }

  Future<bool> _requestPermission(UsbDevice device) async {
    final granted = await FlutterUsbSerial.requestPermission(device);
    if (!mounted) return false;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('USB permission denied for ${device.displayName}'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
    return granted;
  }

  Future<int?> _selectPort(UsbDevice device) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Select port on ${device.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            device.portCount,
            (i) => ListTile(
              leading: const Icon(Icons.settings_input_component),
              title: Text('Port $i'),
              onTap: () => Navigator.pop(ctx, i),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: Row(
          children: [
            Icon(Icons.usb, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'USB Serial',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          if (!_webSerialUnsupported)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _loadDevices,
            ),
        ],
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    // Unsupported browser banner.
    if (_webSerialUnsupported) {
      return _buildUnsupportedBrowser(cs);
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Error: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadDevices, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDevices,
      // On web always show the list (at minimum the sentinel is present).
      child: _devices.isEmpty ? _buildEmpty(cs) : _buildList(cs),
    );
  }

  Widget _buildUnsupportedBrowser(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.browser_not_supported,
                size: 64, color: cs.error.withOpacity(0.8)),
            const SizedBox(height: 20),
            Text(
              'Web Serial API not supported',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This feature requires Chrome 89+, Edge 89+, or Opera 75+.\n'
              'Firefox and Safari do not support the Web Serial API.',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.usb_off,
                  size: 64, color: cs.onSurface.withOpacity(0.3)),
              const SizedBox(height: 16),
              Text(
                'No USB serial devices found',
                style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'Pull to refresh — previously granted ports will appear here'
                    : 'Connect a USB serial device and pull to refresh',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(0.4),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _devices.length,
      itemBuilder: (_, i) {
        final device = _devices[i];
        final isSentinel =
            kIsWeb && device.deviceId == FlutterUsbSerialWeb.kPickerSentinelId;
        return _DeviceCard(
          device: device,
          isSentinel: isSentinel,
          onTap: () => _onDeviceTapped(device),
          onPermissionTap: () =>
              _requestPermission(device).then((_) => _loadDevices()),
        );
      },
    );
  }
}

// ── Device card widget ────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onTap,
    required this.onPermissionTap,
    this.isSentinel = false,
  });

  final UsbDevice device;
  final VoidCallback onTap;
  final VoidCallback onPermissionTap;
  final bool isSentinel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Sentinel card — "Connect new device…"
    if (isSentinel) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_circle_outline,
                      color: cs.secondary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    device.displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.secondary,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: cs.onSurface.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      );
    }

    final permColor = device.hasPermission
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFF9800);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // USB icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.usb, color: cs.primary, size: 24),
              ),
              const SizedBox(width: 12),

              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'VID: ${device.vid}  PID: ${device.pid}  •  ${device.driverType}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                    if (device.manufacturerName?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        device.manufacturerName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                    if (device.serialNumber?.isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        'S/N: ${device.serialNumber}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: cs.onSurface.withOpacity(0.45),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Permission chip
                        GestureDetector(
                          onTap:
                              device.hasPermission ? null : onPermissionTap,
                          child: _Chip(
                            label: device.hasPermission
                                ? 'Allowed'
                                : 'No permission',
                            icon: device.hasPermission
                                ? Icons.lock_open
                                : Icons.lock_outline,
                            color: permColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Port count chip (not shown on web)
                        if (!kIsWeb)
                          _Chip(
                            label:
                                '${device.portCount} port${device.portCount == 1 ? '' : 's'}',
                            icon: Icons.settings_input_component,
                            color: cs.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right,
                color: cs.onSurface.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
