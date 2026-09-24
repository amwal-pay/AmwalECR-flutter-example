import 'package:flutter/material.dart';

import 'terminal_sign_on_state.dart';

/// What the terminal said about itself, on one line the operator can read.
///
/// Mirrors `TerminalStatusLine` in the native simulator. A till that asks and
/// shows nothing is a till whose operator cannot tell a terminal that refused
/// from one that was never reached, which is the whole reason sign-on exists.
class TerminalStatusLine extends StatelessWidget {
  const TerminalStatusLine({
    super.key,
    required this.signOn,
    required this.onRefresh,
  });

  /// Null before a terminal is selected: nothing has been asked yet.
  final TerminalSignOnState? signOn;

  /// Asks the terminal again.
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final TerminalSignOnState? state = signOn;
    if (state == null) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final bool ready = state is TerminalReady;

    return Card(
      key: const Key('terminalStatus'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Dot(state: state),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _headline(state),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ready
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('refreshSignOn'),
                  tooltip: 'Ask the terminal again',
                  icon: const Icon(Icons.refresh),
                  onPressed: state is TerminalAsking ? null : onRefresh,
                ),
              ],
            ),
            ..._detail(context, state),
          ],
        ),
      ),
    );
  }

  String _headline(TerminalSignOnState state) {
    final StringBuffer text = StringBuffer(switch (state) {
      TerminalAsking() => 'Asking the terminal…',
      TerminalReady() => 'Terminal ready',
      _ => 'Terminal not ready',
    });

    final String? transport = state.transport?.name;
    if (transport != null) text.write(' · $transport');

    final String name = state.capabilities?.terminalName ?? '';
    if (name.isNotEmpty) text.write(' · $name');

    return text.toString();
  }

  List<Widget> _detail(BuildContext context, TerminalSignOnState state) {
    final ThemeData theme = Theme.of(context);

    return switch (state) {
      TerminalAsking() => const <Widget>[],

      // What it permits, so an operator can see the limits the terminal will
      // enforce rather than discovering them on a refusal.
      TerminalReady(:final List<String> permitted) => permitted.isEmpty
          ? const <Widget>[]
          : <Widget>[
              const SizedBox(height: 4),
              Text(
                permitted.join(' · '),
                key: const Key('permittedTransactions'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

      TerminalNotReady(:final String reason) => <Widget>[
        const SizedBox(height: 4),
        Text(
          reason,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],

      // Said plainly, because it is a different fact from a terminal that
      // answered and refused: nothing is known about this one at all.
      TerminalNoAnswer(:final String reason) => <Widget>[
        const SizedBox(height: 4),
        Text(
          'No answer — $reason',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    };
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final TerminalSignOnState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    if (state is TerminalAsking) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state is TerminalReady ? colours.primary : colours.error,
      ),
    );
  }
}
