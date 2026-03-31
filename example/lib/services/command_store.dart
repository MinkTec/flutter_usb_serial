import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/serial_command.dart';

class CommandStore extends ChangeNotifier {
  CommandStore._();
  static final CommandStore instance = CommandStore._();

  static const _kCommandsKey = 'usb_commands_v1';
  static const _kMacrosKey = 'usb_macros_v1';

  final List<SerialCommand> commands = [];
  final List<Macro> macros = [];

  bool _loaded = false;

  /// Must be called once at startup (after WidgetsFlutterBinding.ensureInitialized).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();

    final commandsJson = prefs.getString(_kCommandsKey);
    if (commandsJson != null) {
      final list = json.decode(commandsJson) as List<dynamic>;
      commands.addAll(
        list.map((e) => SerialCommand.fromJson(e as Map<String, dynamic>)),
      );
    }

    final macrosJson = prefs.getString(_kMacrosKey);
    if (macrosJson != null) {
      final list = json.decode(macrosJson) as List<dynamic>;
      macros.addAll(
        list.map((e) => Macro.fromJson(e as Map<String, dynamic>)),
      );
    }

    notifyListeners();
  }

  // ── Commands ─────────────────────────────────────────────────────────────────

  SerialCommand newCommand() => SerialCommand(
        id: _newId(),
        name: '',
        payload: '',
        hexMode: false,
        eol: 'LF',
      );

  Future<void> saveCommand(SerialCommand cmd) async {
    final idx = commands.indexWhere((c) => c.id == cmd.id);
    if (idx >= 0) {
      commands[idx] = cmd;
    } else {
      commands.add(cmd);
    }
    await _persistCommands();
    notifyListeners();
  }

  Future<void> deleteCommand(String id) async {
    commands.removeWhere((c) => c.id == id);
    // Remove orphaned macro steps
    for (final macro in macros) {
      macro.steps.removeWhere((s) => s.commandId == id);
    }
    await _persistCommands();
    await _persistMacros();
    notifyListeners();
  }

  // ── Macros ────────────────────────────────────────────────────────────────────

  Macro newMacro() => Macro(
        id: _newId(),
        name: '',
        steps: [],
      );

  Future<void> saveMacro(Macro macro) async {
    final idx = macros.indexWhere((m) => m.id == macro.id);
    if (idx >= 0) {
      macros[idx] = macro;
    } else {
      macros.add(macro);
    }
    await _persistMacros();
    notifyListeners();
  }

  Future<void> deleteMacro(String id) async {
    macros.removeWhere((m) => m.id == id);
    await _persistMacros();
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────────

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${commands.length + macros.length}';

  Future<void> _persistCommands() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCommandsKey,
      json.encode(commands.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _persistMacros() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kMacrosKey,
      json.encode(macros.map((m) => m.toJson()).toList()),
    );
  }
}
