import 'package:amwal_ecr/amwal_ecr.dart';

/// What the till knows about the selected terminal, for the status line.
///
/// Mirrors `TerminalSignOnState.kt` in the native simulator, and keeps the
/// four states apart on purpose. The one that matters is the difference
/// between [TerminalNotReady] and [TerminalNoAnswer]: a terminal that answered
/// and cannot serve is a working link with a reason attached, and one that said
/// nothing is a terminal nothing is known about. Showing them the same way
/// sends an operator to check a network that is fine.
sealed class TerminalSignOnState {
  const TerminalSignOnState();

  /// What the terminal reported, where it reported anything.
  EcrTerminalCapabilities? get capabilities => null;

  /// The transport its profile puts it on, where it named one this package
  /// knows.
  EcrTransport? get transport => capabilities?.transport;
}

/// The request is out.
final class TerminalAsking extends TerminalSignOnState {
  const TerminalAsking();
}

/// It answered and is in service.
final class TerminalReady extends TerminalSignOnState {
  const TerminalReady(this._capabilities);

  final EcrTerminalCapabilities _capabilities;

  @override
  EcrTerminalCapabilities? get capabilities => _capabilities;

  /// The operations it permits, as a till would list them.
  List<String> get permitted => <String>[
    for (final EcrPermittedTransaction entry in _capabilities.permitted)
      entry.maxAmount.isEmpty
          ? entry.type.displayName
          : '${entry.type.displayName} ≤ ${entry.maxAmount}',
  ];
}

/// It answered and cannot serve a transaction, and said why.
final class TerminalNotReady extends TerminalSignOnState {
  const TerminalNotReady(this.reason, this._capabilities);

  /// The terminal's own words. The difference between "wait a moment" and "go
  /// and sign in on the terminal".
  final String reason;

  final EcrTerminalCapabilities _capabilities;

  @override
  EcrTerminalCapabilities? get capabilities => _capabilities;
}

/// Nothing came back. Nothing is claimed about the terminal.
final class TerminalNoAnswer extends TerminalSignOnState {
  const TerminalNoAnswer(this.reason);

  /// Why the terminal could not be asked.
  final String reason;
}

/// Reads a sign-on answer into the state the status line shows.
TerminalSignOnState terminalStateOf(EcrSignOn answer) => switch (answer) {
  EcrSignOnAvailable(:final EcrTerminalCapabilities capabilities) =>
    TerminalReady(capabilities),
  EcrSignOnUnavailable(
    :final String reason,
    :final EcrTerminalCapabilities capabilities,
  ) =>
    TerminalNotReady(reason, capabilities),
  EcrSignOnFailed(:final EcrFailure failure) =>
    TerminalNoAnswer(failure.message),
};
