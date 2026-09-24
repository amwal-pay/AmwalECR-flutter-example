import 'dart:async';

import 'package:amwal_ecr/amwal_ecr.dart';
import 'package:flutter/foundation.dart';

import '../../data/ecr_mode.dart';
import '../../data/ecr_simulator_settings.dart';
import '../../data/terminal.dart';
import '../../data/terminal_repository.dart';
import 'selected_terminal_config.dart';
import 'terminal_sign_on_state.dart';
import 'transaction_state.dart';

class TransactionController extends ChangeNotifier {
  TransactionController(this._repository);

  final TerminalRepository _repository;
  EcrSimulatorSettings? _settings;

  TransactionState _state = const TransactionIdle();
  TransactionState get state => _state;

  SelectedTerminalConfig? _selectedConfig;
  SelectedTerminalConfig? get selectedConfig => _selectedConfig;

  Future<void> _ensureSettings() async {
    _settings ??= await EcrSimulatorSettings.load();
  }

  Future<SelectedTerminalConfig> _resolveConfig(Terminal terminal) async {
    await _ensureSettings();
    final EcrSimulatorSettings settings = _settings!;
    return SelectedTerminalConfig.resolve(
      terminal: terminal,
      environment: settings.environment,
      secureHashKey: settings.secureHashKeyFor(terminal.mode),
    );
  }

  Future<void> updateSelectedTerminal(Terminal? terminal) async {
    if (terminal == null) {
      _selectedConfig = null;
      notifyListeners();
      return;
    }
    _selectedConfig = await _resolveConfig(terminal);
    notifyListeners();
    unawaited(_refreshCapabilities(terminal));
  }

  /// What the till knows about the selected terminal, for the status line.
  ///
  /// Null before any terminal is selected. A till should read
  /// [TerminalReady.capabilities] before offering a button: TMS can disable an
  /// operation or move a limit at any moment, and this is the only way to find
  /// out short of being refused.
  TerminalSignOnState? get signOn => _signOn;
  TerminalSignOnState? _signOn;

  /// Asks the terminal what it is, in the background.
  ///
  /// Not awaited by the caller and never thrown: a sign-on that fails leaves
  /// the till exactly as it was before sign-on existed, offering everything and
  /// finding out from the refusal. It is *shown*, though — an operator looking
  /// at the till should be able to see that the terminal was asked and what it
  /// said. Over Web Service, and on a platform that cannot address the terminal
  /// directly, it is refused before anything is sent, which is an answer rather
  /// than a fault.
  Future<void> _refreshCapabilities(Terminal terminal) async {
    final SelectedTerminalConfig active = await _resolveConfig(terminal);

    // App to app is not asked at all, and neither is Web Service. There the
    // sign-on would cost a handover the operator watches, to learn something
    // the next refusal carries anyway — see EcrTransport.supportsSignOn. No
    // status line is better than one claiming a terminal was not ready when
    // nothing was asked of it.
    if (active.usesPaymentApp || active.usesWebService) {
      _signOn = null;
      notifyListeners();
      return;
    }

    _signOn = const TerminalAsking();
    notifyListeners();
    final EcrSignOn answer = await _terminalFor(terminal, active).signOn();

    // Dropped if the operator has moved on to another terminal meanwhile.
    if (_selectedConfig?.terminal.serialNumber != terminal.serialNumber) return;

    _signOn = terminalStateOf(answer);
    notifyListeners();
  }

  /// Asks again, for the button on the status line.
  Future<void> refreshSignOn() async {
    final Terminal? terminal = _selectedConfig?.terminal;
    if (terminal == null) return;
    await _refreshCapabilities(terminal);
  }

  void _emit(TransactionState next) {
    _state = next;
    notifyListeners();
  }

  void resultAcknowledged() => _emit(const TransactionIdle());

  /// Tells the terminal the cashier has finished, so it can put its receipt
  /// away and be ready for the next transaction.
  ///
  /// The terminal leaves its receipt up until somebody dismisses it, and when
  /// a till drove the transaction nobody is standing there to do it. Closing
  /// the result dialog is the moment the cashier is done, so it is the moment
  /// to say so.
  ///
  /// Deliberately silent, and not something the dialog waits for. The dialog
  /// closes on the operator's tap either way, and a till that cannot tidy the
  /// terminal's screen has not failed at anything the cashier needs to hear
  /// about: on an older terminal, or over Web Service, this is simply refused
  /// and the receipt stays up exactly as it always did.
  Future<void> closeTerminalReceipt(String terminalSerial) async {
    final Terminal? registered = await _repository.findBySerial(terminalSerial);
    if (registered == null) return;

    final SelectedTerminalConfig active = await _resolveConfig(registered);

    // Not for the payment app on this device, and not because it would fail —
    // because it has already happened. An app-to-app answer is held until the
    // operator closes the receipt, so the terminal is idle again by the time
    // this dialog appeared. Sending it anyway brought the payment app to the
    // front for a moment and sent it away again, for nothing.
    if (!active.ecrTransport.supportsCloseReceipt) return;

    await _terminalFor(registered, active).closeReceipt();
  }

  Future<void> startTransaction(TransactionRequest request) async {
    if (_state.isBusy) return;

    _emit(const TransactionChecking());

    final Terminal? registered =
        await _repository.findBySerial(request.terminalSerial);
    if (registered == null) {
      _emit(TransactionFailed(
        'Terminal ${request.terminalSerial} is no longer registered',
      ));
      return;
    }

    final SelectedTerminalConfig active = await _resolveConfig(registered);
    _selectedConfig = active;

    if (!active.isReady) {
      _emit(TransactionFailed(active.issues.join('\n')));
      return;
    }

    final EcrTerminal terminal = _terminalFor(registered, active);

    if (active.usesLocalTerminal) {
      final EcrReachability probe = await terminal.probeReachability();
      if (!probe.reachable) {
        final String message = (StringBuffer()
              ..write('${probe.endpoint} is not reachable')
              ..write(probe.error == null ? '' : '\n(${probe.error})')
              ..write('\n\n')
              ..write(
                active.usesPaymentApp
                    ? 'Check:\n'
                        '• The Amwal payment app is installed on this device\n'
                        '• It is a build that accepts app-to-app requests\n'
                        '• The merchant is signed in — open it once and sign in\n'
                        '• The application ID matches (${probe.endpoint})\n'
                        '• Serial number matches the terminal this app drives'
                    : active.usesUsbCable
                    ? 'Check:\n'
                        '• The USB cable is connected to the terminal\n'
                        '• POS app is in ECR mode (USB cable) and says it is waiting\n'
                        '• Serial number matches the terminal you selected\n'
                        '• This device can act as a USB host (OTG)'
                    : 'Check:\n'
                        '• POS app is in ECR mode (Wi‑Fi) and shows its IP under the card logos\n'
                        '• Registered IP matches that address (port ${probe.port})\n'
                        '• Serial number matches the terminal you selected\n'
                        '• Both devices are on the same Wi‑Fi network\n'
                        '• If testing on one phone, try IP 127.0.0.1',
              ))
            .toString();
        _emit(TransactionFailed(message));
        return;
      }
    }

    _emit(const TransactionInProgress());

    if (request.type == EcrTransactionType.inquiry) {
      final EcrInquiry inquiry = request.looksUpByReference
          ? await terminal.inquireByReference(
              request.originalReference,
              transactionDate: request.transactionDate,
              originalTerminalId: request.originalTerminalId,
              merchantReference: request.merchantReference,
            )
          : await terminal.inquire(
              receiptNumber: request.receiptNumber,
              transactionDate: request.transactionDate,
              originalTerminalId: request.originalTerminalId,
            );
      _emit(switch (inquiry) {
        EcrInquiryFailed(:final EcrFailure failure) =>
          TransactionFailed(failure.message),
        _ => TransactionInquired(inquiry: inquiry, request: request),
      });
      return;
    }

    final EcrResult result = switch (request.type) {
      EcrTransactionType.sale => await terminal.sale(
          request.amount!,
          merchantReference: request.merchantReference,
        ),
      EcrTransactionType.voidTransaction => await terminal.voidTransaction(
          request.receiptNumber,
          originalTerminalId: request.originalTerminalId,
        ),
      EcrTransactionType.refund => await terminal.refund(
          request.amount!,
          receiptNumber: request.receiptNumber,
          transactionDate: request.transactionDate,
          originalTerminalId: request.originalTerminalId,
        ),
      EcrTransactionType.inquiry ||
      EcrTransactionType.receipt ||
      EcrTransactionType.signOn ||
      EcrTransactionType.closeReceipt =>
        throw StateError('${request.type.displayName} is not run from here'),
    };

    _emit(switch (result) {
      EcrFailed() => _failureOf(result, request),
      _ => TransactionCompleted(result, request.type),
    });
  }

  TransactionState _failureOf(EcrFailed result, TransactionRequest request) {
    final EcrInquiry? recovered = result.recovered;
    if (recovered is EcrInquiryFound) {
      return TransactionInquired(
        inquiry: recovered,
        request: request.copyWith(
          type: EcrTransactionType.inquiry,
          originalReference: result.merchantReference,
        ),
      );
    }

    return TransactionFailed(
      result.failure.message,
      inquirableReference: result.merchantReference,
    );
  }

  void inquireAboutReference(String reference, String terminalSerial) {
    if (_state.isBusy) return;

    startTransaction(TransactionRequest(
      type: EcrTransactionType.inquiry,
      terminalSerial: terminalSerial,
      amount: null,
      originalReference: reference,
      merchantReference: reference,
    ));
  }

  Future<void> requestReceipt() async {
    final TransactionState current = _state;
    if (current is! TransactionInquired || current.fetchingReceipt) return;

    _emit(current.copyWith(fetchingReceipt: true));

    final Terminal? registered =
        await _repository.findBySerial(current.request.terminalSerial);
    if (registered == null) {
      _emit(current.copyWith(
        fetchingReceipt: false,
        receipt: EcrReceiptUnavailable(
          merchantReference: '',
          reason: 'Terminal ${current.request.terminalSerial} '
              'is no longer registered',
          raw: '',
        ),
      ));
      return;
    }

    final SelectedTerminalConfig active = await _resolveConfig(registered);
    if (!active.usesLocalTerminal) {
      _emit(current.copyWith(
        fetchingReceipt: false,
        receipt: const EcrReceiptUnavailable(
          merchantReference: '',
          reason: 'Receipt fetch is only supported over Wi‑Fi / USB cable ECR',
          raw: '',
        ),
      ));
      return;
    }

    final EcrInquiry inquiry = current.inquiry;
    final EcrTransaction? found =
        inquiry is EcrInquiryFound ? inquiry.transaction : null;

    final String receiptNumber = switch (found?.stan) {
      final String stan when stan.trim().isNotEmpty => stan,
      _ => current.request.receiptNumber,
    };

    if (receiptNumber.trim().isEmpty) {
      _emit(current.copyWith(
        fetchingReceipt: false,
        receipt: const EcrReceiptUnavailable(
          merchantReference: '',
          reason: 'This transaction has no receipt number to fetch a receipt by',
          raw: '',
        ),
      ));
      return;
    }

    final String transactionDate = switch (_dayOf(found?.transactionTime)) {
      final String day when day.isNotEmpty => day,
      _ => current.request.transactionDate,
    };

    final EcrReceipt receipt = await _terminalFor(registered, active).receipt(
      receiptNumber: receiptNumber,
      transactionDate: transactionDate,
      originalTerminalId: current.request.originalTerminalId,
    );

    final TransactionState latest = _state;
    if (latest is! TransactionInquired) return;
    _emit(latest.copyWith(receipt: receipt, fetchingReceipt: false));
  }

  static String _dayOf(String? transactionTime) {
    final String digits =
        (transactionTime ?? '').replaceAll(RegExp('[^0-9]'), '');
    return digits.length >= 8 ? digits.substring(0, 8) : '';
  }

  /// The SDK terminal for one registered terminal.
  ///
  /// Transport and host come from [SelectedTerminalConfig] rather than being
  /// mapped again here. The native app kept two copies of that mapping and they
  /// drifted the moment a transport needed something the others did not — a
  /// terminal registered as app to app planned correctly in one place and
  /// crashed in the other.
  EcrTerminal _terminalFor(Terminal terminal, SelectedTerminalConfig active) =>
      EcrSessions.open(
        host: active.ecrHost,
        serialNumber: terminal.serialNumber,
        transport: active.ecrTransport,
        config: active.ecrConfig,
      ).terminal;
}
