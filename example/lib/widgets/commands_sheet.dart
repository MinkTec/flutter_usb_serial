import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/serial_command.dart';
import '../services/command_store.dart';

// ── Public API ─────────────────────────────────────────────────────────────────

typedef SendBytesCallback = Future<bool> Function(Uint8List data);

class CommandsSheet extends StatefulWidget {
  const CommandsSheet({
    super.key,
    required this.sendBytes,
    required this.isConnected,
  });

  final SendBytesCallback sendBytes;
  final ValueListenable<bool> isConnected;

  @override
  State<CommandsSheet> createState() => _CommandsSheetState();
}

// ── Sheet state ────────────────────────────────────────────────────────────────

class _CommandsSheetState extends State<CommandsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String? _runningMacroId;
  bool _macroAborted = false;
  int _macroStep = 0;
  int _macroTotalSteps = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Macro runner ─────────────────────────────────────────────────────────────

  Future<void> _runMacro(Macro macro) async {
    final store = CommandStore.instance;
    final validSteps = macro.steps.where((s) {
      return store.commands.any((c) => c.id == s.commandId);
    }).toList();

    if (validSteps.isEmpty) return;

    setState(() {
      _runningMacroId = macro.id;
      _macroAborted = false;
      _macroStep = 0;
      _macroTotalSteps = validSteps.length;
    });

    for (var i = 0; i < validSteps.length; i++) {
      if (_macroAborted) break;

      final step = validSteps[i];
      final cmd = store.commands.firstWhere((c) => c.id == step.commandId);
      final bytes = cmd.buildPayload();

      setState(() => _macroStep = i + 1);

      await widget.sendBytes(bytes);

      if (step.delayAfterMs > 0 && !_macroAborted) {
        await Future.delayed(Duration(milliseconds: step.delayAfterMs));
      }
    }

    if (mounted) {
      setState(() {
        _runningMacroId = null;
        _macroAborted = false;
      });
    }
  }

  void _stopMacro() {
    setState(() => _macroAborted = true);
  }

  // ── Command actions ───────────────────────────────────────────────────────────

  Future<void> _addCommand() async {
    final blank = CommandStore.instance.newCommand();
    final result = await showDialog<SerialCommand>(
      context: context,
      builder: (_) => _CommandEditorDialog(initial: blank),
    );
    if (result != null) await CommandStore.instance.saveCommand(result);
  }

  Future<void> _editCommand(SerialCommand cmd) async {
    final result = await showDialog<SerialCommand>(
      context: context,
      builder: (_) => _CommandEditorDialog(initial: cmd),
    );
    if (result != null) await CommandStore.instance.saveCommand(result);
  }

  Future<void> _deleteCommand(SerialCommand cmd) async {
    final ok = await _confirmDelete(context, '"${cmd.name}"');
    if (ok) await CommandStore.instance.deleteCommand(cmd.id);
  }

  Future<void> _addMacro() async {
    final blank = CommandStore.instance.newMacro();
    final result = await showDialog<Macro>(
      context: context,
      builder: (_) => _MacroEditorDialog(initial: blank),
    );
    if (result != null) await CommandStore.instance.saveMacro(result);
  }

  Future<void> _editMacro(Macro macro) async {
    final result = await showDialog<Macro>(
      context: context,
      builder: (_) => _MacroEditorDialog(initial: macro),
    );
    if (result != null) await CommandStore.instance.saveMacro(result);
  }

  Future<void> _deleteMacro(Macro macro) async {
    final ok = await _confirmDelete(context, '"${macro.name}"');
    if (ok) await CommandStore.instance.deleteMacro(macro.id);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.65;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Running macro banner
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: _runningMacroId != null
                ? _MacroBanner(
                    step: _macroStep,
                    total: _macroTotalSteps,
                    macroName: CommandStore.instance.macros
                        .firstWhere((m) => m.id == _runningMacroId,
                            orElse: () =>
                                Macro(id: '', name: 'Macro', steps: []))
                        .name,
                    onStop: _stopMacro,
                  )
                : const SizedBox.shrink(),
          ),
          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF58A6FF),
            unselectedLabelColor: Colors.white38,
            indicatorColor: const Color(0xFF58A6FF),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Commands'),
              Tab(text: 'Macros'),
            ],
          ),
          // Tab body
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CommandsTab(
                  isConnected: widget.isConnected,
                  sendBytes: widget.sendBytes,
                  onAdd: _addCommand,
                  onEdit: _editCommand,
                  onDelete: _deleteCommand,
                ),
                _MacrosTab(
                  isConnected: widget.isConnected,
                  runningMacroId: _runningMacroId,
                  onAdd: _addMacro,
                  onEdit: _editMacro,
                  onDelete: _deleteMacro,
                  onRun: _runMacro,
                  onStop: _stopMacro,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Macro banner ───────────────────────────────────────────────────────────────

class _MacroBanner extends StatelessWidget {
  const _MacroBanner({
    required this.macroName,
    required this.step,
    required this.total,
    required this.onStop,
  });

  final String macroName;
  final int step;
  final int total;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade900.withOpacity(0.85),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.play_arrow, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Running "$macroName"  •  step $step / $total',
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Stop',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Commands tab ───────────────────────────────────────────────────────────────

class _CommandsTab extends StatelessWidget {
  const _CommandsTab({
    required this.isConnected,
    required this.sendBytes,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final ValueListenable<bool> isConnected;
  final SendBytesCallback sendBytes;
  final VoidCallback onAdd;
  final ValueChanged<SerialCommand> onEdit;
  final ValueChanged<SerialCommand> onDelete;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CommandStore.instance,
      builder: (context, _) {
        final cmds = CommandStore.instance.commands;
        return Stack(
          children: [
            cmds.isEmpty
                ? const Center(
                    child: Text(
                      'No commands saved.\nTap + to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 72),
                    itemCount: cmds.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, i) => _CommandTile(
                      cmd: cmds[i],
                      isConnected: isConnected,
                      sendBytes: sendBytes,
                      onEdit: () => onEdit(cmds[i]),
                      onDelete: () => onDelete(cmds[i]),
                    ),
                  ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'add_command',
                onPressed: onAdd,
                backgroundColor: const Color(0xFF238636),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Command tile ───────────────────────────────────────────────────────────────

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.cmd,
    required this.isConnected,
    required this.sendBytes,
    required this.onEdit,
    required this.onDelete,
  });

  final SerialCommand cmd;
  final ValueListenable<bool> isConnected;
  final SendBytesCallback sendBytes;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isConnected,
      builder: (context, connected, _) {
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge(
                label: cmd.hexMode ? 'HEX' : 'ASCII',
                color:
                    cmd.hexMode ? Colors.purple.shade300 : Colors.teal.shade300,
              ),
              const SizedBox(height: 4),
              _Badge(
                label: cmd.eol == 'none' ? 'NO EOL' : cmd.eol,
                color: Colors.orange.shade300,
              ),
            ],
          ),
          title: Text(
            cmd.name.isEmpty ? '(unnamed)' : cmd.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          ),
          subtitle: Text(
            cmd.payload.isEmpty ? '(empty)' : cmd.payload,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Send
              IconButton(
                icon: const Icon(Icons.send, size: 18),
                tooltip: 'Send',
                color: connected ? Colors.green.shade400 : Colors.white24,
                onPressed:
                    connected ? () => sendBytes(cmd.buildPayload()) : null,
              ),
              // Edit
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                color: Colors.white54,
                onPressed: onEdit,
              ),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                color: Colors.red.shade300,
                onPressed: onDelete,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Macros tab ─────────────────────────────────────────────────────────────────

class _MacrosTab extends StatelessWidget {
  const _MacrosTab({
    required this.isConnected,
    required this.runningMacroId,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
    required this.onStop,
  });

  final ValueListenable<bool> isConnected;
  final String? runningMacroId;
  final VoidCallback onAdd;
  final ValueChanged<Macro> onEdit;
  final ValueChanged<Macro> onDelete;
  final ValueChanged<Macro> onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CommandStore.instance,
      builder: (context, _) {
        final ms = CommandStore.instance.macros;
        return Stack(
          children: [
            ms.isEmpty
                ? const Center(
                    child: Text(
                      'No macros saved.\nTap + to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white38,
                          fontFamily: 'monospace',
                          fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 72),
                    itemCount: ms.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, i) => _MacroTile(
                      macro: ms[i],
                      isConnected: isConnected,
                      isRunning: runningMacroId == ms[i].id,
                      onRun: () => onRun(ms[i]),
                      onStop: onStop,
                      onEdit: () => onEdit(ms[i]),
                      onDelete: () => onDelete(ms[i]),
                    ),
                  ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'add_macro',
                onPressed: onAdd,
                backgroundColor: const Color(0xFF238636),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Macro tile ─────────────────────────────────────────────────────────────────

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.macro,
    required this.isConnected,
    required this.isRunning,
    required this.onRun,
    required this.onStop,
    required this.onEdit,
    required this.onDelete,
  });

  final Macro macro;
  final ValueListenable<bool> isConnected;
  final bool isRunning;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isConnected,
      builder: (context, connected, _) {
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          title: Text(
            macro.name.isEmpty ? '(unnamed)' : macro.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          ),
          subtitle: Text(
            '${macro.steps.length} step${macro.steps.length == 1 ? '' : 's'}',
            style: const TextStyle(
                color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Run / Stop
              IconButton(
                icon: Icon(
                  isRunning ? Icons.stop_circle_outlined : Icons.play_arrow,
                  size: 20,
                ),
                tooltip: isRunning ? 'Stop' : 'Run',
                color: isRunning
                    ? Colors.orange.shade300
                    : (connected ? Colors.green.shade400 : Colors.white24),
                onPressed: isRunning ? onStop : (connected ? onRun : null),
              ),
              // Edit
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit',
                color: Colors.white54,
                onPressed: onEdit,
              ),
              // Delete
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete',
                color: Colors.red.shade300,
                onPressed: onDelete,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Command editor dialog ──────────────────────────────────────────────────────

class _CommandEditorDialog extends StatefulWidget {
  const _CommandEditorDialog({required this.initial});

  final SerialCommand initial;

  @override
  State<_CommandEditorDialog> createState() => _CommandEditorDialogState();
}

class _CommandEditorDialogState extends State<_CommandEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _payloadCtrl;
  late bool _hexMode;
  late String _eol;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.name);
    _payloadCtrl = TextEditingController(text: widget.initial.payload);
    _hexMode = widget.initial.hexMode;
    _eol = widget.initial.eol;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C2128),
      title: const Text('Command',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(
              controller: _nameCtrl,
              label: 'Name',
              hint: 'e.g. Reset',
            ),
            const SizedBox(height: 12),
            _dialogField(
              controller: _payloadCtrl,
              label: 'Payload',
              hint: _hexMode ? 'hex bytes (e.g. 41 42 0D)' : 'ASCII text',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hex mode',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              value: _hexMode,
              onChanged: (v) => setState(() => _hexMode = v),
              activeColor: Colors.purple.shade300,
            ),
            Row(
              children: [
                const Text('EOL: ',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace')),
                DropdownButton<String>(
                  value: _eol,
                  isDense: true,
                  dropdownColor: const Color(0xFF1C2128),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                  underline: Container(height: 1, color: Colors.white24),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('None')),
                    DropdownMenuItem(value: 'CR', child: Text('CR')),
                    DropdownMenuItem(value: 'LF', child: Text('LF')),
                    DropdownMenuItem(value: 'CRLF', child: Text('CR+LF')),
                  ],
                  onChanged: (v) => setState(() => _eol = v!),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        FilledButton(
          onPressed: () {
            final cmd = widget.initial.copyWith(
              name: _nameCtrl.text.trim(),
              payload: _payloadCtrl.text,
              hexMode: _hexMode,
              eol: _eol,
            );
            Navigator.pop(context, cmd);
          },
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFF238636)),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
          color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(
            color: Colors.white24, fontSize: 12, fontFamily: 'monospace'),
        filled: true,
        fillColor: const Color(0xFF0D1117),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          borderSide: const BorderSide(color: Color(0xFF58A6FF), width: 1.5),
        ),
      ),
    );
  }
}

// ── Macro editor dialog ────────────────────────────────────────────────────────

class _MacroEditorDialog extends StatefulWidget {
  const _MacroEditorDialog({required this.initial});

  final Macro initial;

  @override
  State<_MacroEditorDialog> createState() => _MacroEditorDialogState();
}

class _MacroEditorDialogState extends State<_MacroEditorDialog> {
  late final TextEditingController _nameCtrl;
  late List<MacroStep> _steps;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.name);
    _steps = widget.initial.steps.map((s) => s.copyWith()).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _addStep() {
    final cmds = CommandStore.instance.commands;
    if (cmds.isEmpty) return;
    setState(() {
      _steps.add(MacroStep(commandId: cmds.first.id));
    });
  }

  void _removeStep(int idx) => setState(() => _steps.removeAt(idx));

  @override
  Widget build(BuildContext context) {
    final cmds = CommandStore.instance.commands;
    final noCommands = cmds.isEmpty;

    return AlertDialog(
      backgroundColor: const Color(0xFF1C2128),
      title: const Text('Macro',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle:
                    const TextStyle(color: Colors.white54, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  borderSide:
                      const BorderSide(color: Color(0xFF58A6FF), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (noCommands)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Text(
                  'Create commands first.',
                  style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              )
            else ...[
              // Steps list
              if (_steps.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _steps.length,
                    itemBuilder: (_, i) => _StepRow(
                      index: i,
                      step: _steps[i],
                      commands: cmds,
                      onCommandChanged: (id) => setState(
                          () => _steps[i] = _steps[i].copyWith(commandId: id)),
                      onDelayChanged: (ms) => setState(() =>
                          _steps[i] = _steps[i].copyWith(delayAfterMs: ms)),
                      onDelete: () => _removeStep(i),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: noCommands ? null : _addStep,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add step'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF58A6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        FilledButton(
          onPressed: () {
            final macro = widget.initial.copyWith(
              name: _nameCtrl.text.trim(),
              steps: _steps,
            );
            Navigator.pop(context, macro);
          },
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFF238636)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ── Step row ───────────────────────────────────────────────────────────────────

class _StepRow extends StatefulWidget {
  const _StepRow({
    required this.index,
    required this.step,
    required this.commands,
    required this.onCommandChanged,
    required this.onDelayChanged,
    required this.onDelete,
  });

  final int index;
  final MacroStep step;
  final List<SerialCommand> commands;
  final ValueChanged<String> onCommandChanged;
  final ValueChanged<int> onDelayChanged;
  final VoidCallback onDelete;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  late final TextEditingController _delayCtrl;

  @override
  void initState() {
    super.initState();
    _delayCtrl = TextEditingController(
        text: widget.step.delayAfterMs > 0
            ? widget.step.delayAfterMs.toString()
            : '');
  }

  @override
  void dispose() {
    _delayCtrl.dispose();
    super.dispose();
  }

  // Ensure the current commandId exists; fall back to first if not
  String _validCommandId() {
    final ids = widget.commands.map((c) => c.id).toSet();
    return ids.contains(widget.step.commandId)
        ? widget.step.commandId
        : widget.commands.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Index label
          SizedBox(
            width: 24,
            child: Text(
              '#${widget.index + 1}',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          // Command dropdown
          Expanded(
            child: DropdownButton<String>(
              value: _validCommandId(),
              isExpanded: true,
              isDense: true,
              dropdownColor: const Color(0xFF1C2128),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
              underline: Container(height: 1, color: Colors.white24),
              items: widget.commands
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          c.name.isEmpty ? '(unnamed)' : c.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (id) => widget.onCommandChanged(id!),
            ),
          ),
          const SizedBox(width: 8),
          // Delay field
          SizedBox(
            width: 64,
            child: TextField(
              controller: _delayCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                suffixText: 'ms',
                suffixStyle:
                    const TextStyle(color: Colors.white38, fontSize: 10),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF58A6FF)),
                ),
              ),
              onChanged: (v) => widget.onDelayChanged(int.tryParse(v) ?? 0),
            ),
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: Colors.red.shade300,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Badge ──────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Future<bool> _confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1C2128),
      title: const Text('Delete',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: Text(
        'Delete $name?',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}
