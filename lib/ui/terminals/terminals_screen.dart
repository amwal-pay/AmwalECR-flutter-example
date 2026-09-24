import 'dart:async';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';

import '../../data/ecr_simulator_settings.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import '../components/environment_selector.dart';
import '../transaction/selected_terminal_config.dart';
import '../transaction/terminal_sign_on_state.dart';
import 'terminal_card.dart';
import 'terminal_edit_screen.dart';

class TerminalsScreen extends StatefulWidget {
  const TerminalsScreen({super.key, required this.repository});

  final TerminalRepository repository;

  @override
  State<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends State<TerminalsScreen> {
  List<Terminal> _terminals = const <Terminal>[];
  EcrSimulatorSettings? _settings;

  /// What each terminal said when the operator last pressed Check, by serial.
  ///
  /// **Nothing is asked on its own here.** Opening this screen to rename a
  /// terminal should not start a round of handshakes across every registered
  /// one — some are not on this network and one is a cable. The operator asks
  /// when they want to know, and the transaction screen asks the one it is
  /// about to use.
  final Map<String, TerminalSignOnState> _signOns =
      <String, TerminalSignOnState>{};

  /// Asks one terminal what it is.
  ///
  /// App to app and Web Service are not asked at all — see
  /// `EcrTransport.supportsSignOn`. The button says so rather than pretending
  /// to ask: "this link is not asked" is a different fact from "it did not
  /// answer", and an operator who cannot tell them apart goes looking for a
  /// fault that is not there.
  Future<void> _check(Terminal terminal) async {
    final EcrSimulatorSettings settings =
        _settings ?? await EcrSimulatorSettings.load();
    final SelectedTerminalConfig active = SelectedTerminalConfig.resolve(
      terminal: terminal,
      environment: settings.environment,
      secureHashKey: settings.secureHashKeyFor(terminal.mode),
    );

    if (!active.ecrTransport.supportsSignOn) {
      setState(() {
        _signOns[terminal.serialNumber] = TerminalNoAnswer(
          '${terminal.mode.label} is not asked — it reports through the '
          'transaction that uses it',
        );
      });
      return;
    }

    setState(() => _signOns[terminal.serialNumber] = const TerminalAsking());

    final EcrSignOn answer = await EcrSessions.open(
      host: active.ecrHost,
      serialNumber: terminal.serialNumber,
      transport: active.ecrTransport,
      config: active.ecrConfig,
    ).terminal.signOn();

    if (!mounted) return;
    setState(() => _signOns[terminal.serialNumber] = terminalStateOf(answer));
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Terminal> terminals = await widget.repository.observeAll().first;
    final EcrSimulatorSettings settings = await EcrSimulatorSettings.load();
    if (!mounted) return;
    setState(() {
      _terminals = terminals;
      _settings = settings;
    });
  }

  Future<void> _edit([Terminal? terminal]) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => TerminalEditScreen(
          repository: widget.repository,
          original: terminal,
        ),
      ),
    );
    if (saved ?? false) await _reload();
  }

  Future<void> _delete(Terminal terminal) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove terminal'),
        content: Text('Remove ${terminal.name} (${terminal.serialNumber})?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmDelete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.repository.delete(terminal);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final EcrSimulatorSettings? settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS terminals'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addTerminal'),
        onPressed: _edit,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  EcrSimulatorSettingsPanel(
                    environment: settings.environment,
                    wifiSecureHashKey: settings.wifiSecureHashKey,
                    webServiceSecureHashKey: settings.webServiceSecureHashKey,
                    onEnvironmentSelected: (value) {
                      setState(() => settings.environment = value);
                    },
                    onWifiSecureHashKeyChanged: (value) {
                      setState(() => settings.wifiSecureHashKey = value);
                    },
                    onWebServiceSecureHashKeyChanged: (value) {
                      setState(() => settings.webServiceSecureHashKey = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_terminals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No terminals yet.\nTap + to register a POS terminal.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._terminals.map(
                      (Terminal terminal) => TerminalCard(
                        terminal: terminal,
                        signOn: _signOns[terminal.serialNumber],
                        onCheck: () => unawaited(_check(terminal)),
                        onEdit: () => _edit(terminal),
                        onDelete: () => _delete(terminal),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
