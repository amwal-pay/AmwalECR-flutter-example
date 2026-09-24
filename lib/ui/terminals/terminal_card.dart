import 'package:flutter/material.dart';

import '../../data/terminal.dart';
import '../transaction/terminal_sign_on_state.dart';

/// One registered terminal, with what it said about itself when asked.
///
/// Mirrors `TerminalCard` in the native simulator, including the thing that
/// card exists to show: the mode the operator registered here, and the mode the
/// terminal reports it is actually on. They are different facts, and a terminal
/// TMS has moved since it was registered is exactly the case worth seeing at a
/// glance rather than discovering on a refused sale.
class TerminalCard extends StatelessWidget {
  const TerminalCard({
    super.key,
    required this.terminal,
    required this.signOn,
    required this.onCheck,
    required this.onEdit,
    required this.onDelete,
  });

  final Terminal terminal;

  /// Null until the operator has pressed Check. Nothing is asked on its own
  /// here — see the note on the screen.
  final TerminalSignOnState? signOn;

  final VoidCallback onCheck;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TerminalSignOnState? state = signOn;

    return Card(
      key: Key('terminal-${terminal.serialNumber}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Dot(state: state),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    terminal.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _modeLine(state),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            ..._summary(context, state),
            const SizedBox(height: 4),
            Text(
              'S/N ${terminal.serialNumber}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            Text(
              terminal.connectionSummary(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  key: Key('check-${terminal.serialNumber}'),
                  onPressed: state is TerminalAsking ? null : onCheck,
                  child: const Text('Check'),
                ),
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(onPressed: onDelete, child: const Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _modeLine(TerminalSignOnState? state) {
    final StringBuffer text = StringBuffer(terminal.mode.label);
    final String? reported = state?.transport?.name;
    if (reported != null) text.write(' · terminal reports $reported');
    return text.toString();
  }

  List<Widget> _summary(BuildContext context, TerminalSignOnState? state) {
    final ThemeData theme = Theme.of(context);

    return switch (state) {
      null || TerminalAsking() => const <Widget>[],

      TerminalReady(:final List<String> permitted) => permitted.isEmpty
          ? const <Widget>[]
          : <Widget>[
              const SizedBox(height: 2),
              Text(
                permitted.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

      TerminalNotReady(:final String reason) => <Widget>[
        const SizedBox(height: 2),
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
        const SizedBox(height: 2),
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

  final TerminalSignOnState? state;

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

    // Grey until asked: an unasked terminal is not a failed one, and colouring
    // it red would have every freshly registered terminal look broken.
    final Color colour = switch (state) {
      null => colours.outlineVariant,
      TerminalReady() => colours.primary,
      _ => colours.error,
    };

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
    );
  }
}
