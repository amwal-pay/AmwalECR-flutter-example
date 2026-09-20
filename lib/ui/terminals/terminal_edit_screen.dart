import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ecr_mode.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';

/// Adds a terminal, or edits the one whose serial number was passed in.
class TerminalEditScreen extends StatefulWidget {
  const TerminalEditScreen({
    super.key,
    required this.repository,
    this.original,
  });

  final TerminalRepository repository;

  /// The terminal being edited, or null when adding one.
  final Terminal? original;

  @override
  State<TerminalEditScreen> createState() => _TerminalEditScreenState();
}

class _TerminalEditScreenState extends State<TerminalEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.original?.name ?? '');
  late final TextEditingController _serial =
      TextEditingController(text: widget.original?.serialNumber ?? '');
  late EcrMode _mode = widget.original?.mode ?? EcrMode.defaultMode;
  late final TextEditingController _ip =
      TextEditingController(text: widget.original?.ipAddress ?? '');
  late final TextEditingController _port = TextEditingController(
    text: (widget.original?.port ?? 0) > 0
        ? '${widget.original!.port}'
        : widget.original == null
            ? '9100'
            : '',
  );
  late final TextEditingController _merchantId =
      TextEditingController(text: widget.original?.merchantId ?? '');
  late final TextEditingController _terminalId =
      TextEditingController(text: widget.original?.terminalId ?? '');

  /// Which payment app app-to-app hands the transaction to.
  ///
  /// Prefilled with the shipped application id, because that is the answer
  /// every time but a test build.
  late final TextEditingController _packageName = TextEditingController(
    text: widget.original?.packageName.isNotEmpty ?? false
        ? widget.original!.packageName
        : EcrPaymentApp.defaultPackage,
  );

  _TerminalErrors _errors = const _TerminalErrors();
  String? _saveError;

  @override
  void dispose() {
    _name.dispose();
    _serial.dispose();
    _ip.dispose();
    _port.dispose();
    _merchantId.dispose();
    _terminalId.dispose();
    _packageName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saveError = null);

    final _TerminalErrors validated = _validate();
    setState(() => _errors = validated);
    if (validated.any) return;

    final SaveOutcome outcome = await widget.repository.save(
      Terminal(
        serialNumber: _serial.text.trim(),
        name: _name.text.trim(),
        ecrMode: _mode.value,
        ipAddress: _ip.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        merchantId: _merchantId.text.trim(),
        terminalId: _terminalId.text.trim(),
        packageName: _mode.isAppToApp ? _packageName.text.trim() : '',
      ),
      originalSerial: widget.original?.serialNumber,
    );

    if (!mounted) return;
    switch (outcome) {
      case SaveSucceeded():
        Navigator.of(context).pop(true);
      case SaveRejected(:final String reason):
        setState(() => _saveError = reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.original == null ? 'Add terminal' : 'Terminal'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _Field(
              fieldKey: const Key('terminalName'),
              controller: _name,
              label: 'Terminal name',
              error: _errors.name,
              capitalization: TextCapitalization.words,
            ),
            _Field(
              fieldKey: const Key('serialNumber'),
              controller: _serial,
              label: 'Serial number',
              error: _errors.serial ?? _saveError,
              capitalization: TextCapitalization.characters,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'ECR mode',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<EcrMode>(
                    key: const Key('ecrMode'),
                    value: _mode,
                    isExpanded: true,
                    isDense: true,
                    items: EcrMode.values
                        .map(
                          (EcrMode option) => DropdownMenuItem<EcrMode>(
                            key: Key('mode-${option.name}'),
                            value: option,
                            child: Text(
                              option == EcrMode.bluetooth
                                  ? '${option.label} (not supported)'
                                  : option.label,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (EcrMode? value) {
                      if (value != null) setState(() => _mode = value);
                    },
                  ),
                ),
              ),
            ),
            if (_mode.isUsbCable)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Connect the till to the terminal with a USB cable. '
                  'There is no address to enter — the cable is found when it '
                  'is plugged in.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (_mode.isAppToApp) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'The terminal is this device. There is no address: the '
                  'transaction is handed to the Amwal payment app installed '
                  'here, and the serial number still has to be the one that '
                  'app drives.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              _Field(
                fieldKey: const Key('packageName'),
                controller: _packageName,
                label: 'Application ID',
                error: _errors.packageName,
              ),
            ],
            if (_mode.isIpBased) ...<Widget>[
              _Field(
                fieldKey: const Key('ipAddress'),
                controller: _ip,
                label: 'IP address',
                error: _errors.ip,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
              ),
              _Field(
                fieldKey: const Key('port'),
                controller: _port,
                label: 'Port',
                error: _errors.port,
                keyboardType: TextInputType.number,
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ],
            if (_mode == EcrMode.webService) ...<Widget>[
              _Field(
                fieldKey: const Key('merchantId'),
                controller: _merchantId,
                label: 'Merchant ID',
                error: _errors.merchantId,
                keyboardType: TextInputType.number,
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              _Field(
                fieldKey: const Key('terminalId'),
                controller: _terminalId,
                label: 'Terminal ID',
                error: _errors.terminalId,
                keyboardType: TextInputType.number,
                formatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('saveTerminal'),
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _TerminalErrors _validate() {
    final int? portNumber = int.tryParse(_port.text.trim());
    return _TerminalErrors(
      name: _name.text.trim().isEmpty ? 'Enter a terminal name' : null,
      serial:
          _serial.text.trim().isEmpty ? 'Enter the terminal serial number' : null,
      ip: switch (_mode.isIpBased) {
        false => null,
        true => switch (_ip.text.trim()) {
            '' => 'Enter the terminal IP address',
            final String value when !_ipv4.hasMatch(value) =>
              'Enter a valid IPv4 address, for example 192.168.1.50',
            _ => null,
          },
      },
      port: switch (_mode.isIpBased) {
        false => null,
        true => switch (portNumber) {
            null => 'Enter the communication port',
            final int value when value < 1 || value > 65535 =>
              'Port must be between 1 and 65535',
            _ => null,
          },
      },
      merchantId: switch (_mode) {
        EcrMode.webService when _merchantId.text.trim().isEmpty =>
          'Enter the merchant ID',
        EcrMode.webService
            when int.tryParse(_merchantId.text.trim()) == null =>
          'Merchant ID must be numeric',
        _ => null,
      },
      terminalId: switch (_mode) {
        EcrMode.webService when _terminalId.text.trim().isEmpty =>
          'Enter the terminal ID',
        EcrMode.webService
            when int.tryParse(_terminalId.text.trim()) == null =>
          'Terminal ID must be numeric',
        _ => null,
      },
      packageName: switch (_mode.isAppToApp) {
        false => null,
        true => switch (_packageName.text.trim()) {
            '' => 'Enter the payment app application ID',
            final String value when !_applicationId.hasMatch(value) =>
              'Enter an application ID, for example com.amwalpay.pos',
            _ => null,
          },
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.error,
    this.keyboardType = TextInputType.text,
    this.capitalization = TextCapitalization.none,
    this.formatters,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? error;
  final TextInputType keyboardType;
  final TextCapitalization capitalization;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        inputFormatters: formatters,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: error,
        ),
      ),
    );
  }
}

class _TerminalErrors {
  const _TerminalErrors({
    this.name,
    this.serial,
    this.ip,
    this.port,
    this.merchantId,
    this.terminalId,
    this.packageName,
  });

  final String? name;
  final String? serial;
  final String? ip;
  final String? port;
  final String? merchantId;
  final String? terminalId;
  final String? packageName;

  bool get any =>
      name != null ||
      serial != null ||
      ip != null ||
      port != null ||
      merchantId != null ||
      terminalId != null ||
      packageName != null;
}

final RegExp _ipv4 = RegExp(
  r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
);

/// An Android application id, which is what app-to-app has instead of an
/// address. Checked here so an IP typed into that field is caught while the
/// operator is still looking at it.
final RegExp _applicationId = RegExp(r'^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$');
