import 'dart:typed_data';

// ── SerialCommand ──────────────────────────────────────────────────────────────

class SerialCommand {
  SerialCommand({
    required this.id,
    required this.name,
    required this.payload,
    this.hexMode = false,
    this.eol = 'LF',
  });

  final String id;
  String name;
  String payload;
  bool hexMode; // true = payload is hex bytes string, false = ASCII
  String eol; // 'none' | 'CR' | 'LF' | 'CRLF'

  /// Build the bytes to actually send: parse payload + append EOL bytes.
  Uint8List buildPayload() {
    Uint8List base;
    if (hexMode) {
      base = _parseHex(payload) ?? Uint8List(0);
    } else {
      base = Uint8List.fromList(payload.codeUnits);
    }

    final List<int> suffix;
    switch (eol) {
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

  static Uint8List? _parseHex(String s) {
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

  factory SerialCommand.fromJson(Map<String, dynamic> j) => SerialCommand(
        id: j['id'] as String,
        name: j['name'] as String,
        payload: j['payload'] as String,
        hexMode: j['hexMode'] as bool? ?? false,
        eol: j['eol'] as String? ?? 'LF',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'payload': payload,
        'hexMode': hexMode,
        'eol': eol,
      };

  SerialCommand copyWith({
    String? name,
    String? payload,
    bool? hexMode,
    String? eol,
  }) =>
      SerialCommand(
        id: id,
        name: name ?? this.name,
        payload: payload ?? this.payload,
        hexMode: hexMode ?? this.hexMode,
        eol: eol ?? this.eol,
      );
}

// ── MacroStep ──────────────────────────────────────────────────────────────────

class MacroStep {
  MacroStep({required this.commandId, this.delayAfterMs = 0});

  String commandId;
  int delayAfterMs; // delay AFTER this step fires, in milliseconds

  factory MacroStep.fromJson(Map<String, dynamic> j) => MacroStep(
        commandId: j['commandId'] as String,
        delayAfterMs: j['delayAfterMs'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'commandId': commandId,
        'delayAfterMs': delayAfterMs,
      };

  MacroStep copyWith({String? commandId, int? delayAfterMs}) => MacroStep(
        commandId: commandId ?? this.commandId,
        delayAfterMs: delayAfterMs ?? this.delayAfterMs,
      );
}

// ── Macro ──────────────────────────────────────────────────────────────────────

class Macro {
  Macro({required this.id, required this.name, required this.steps});

  final String id;
  String name;
  List<MacroStep> steps;

  factory Macro.fromJson(Map<String, dynamic> j) => Macro(
        id: j['id'] as String,
        name: j['name'] as String,
        steps: (j['steps'] as List<dynamic>? ?? [])
            .map((s) => MacroStep.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  Macro copyWith({String? name, List<MacroStep>? steps}) => Macro(
        id: id,
        name: name ?? this.name,
        steps: steps ?? this.steps,
      );
}
