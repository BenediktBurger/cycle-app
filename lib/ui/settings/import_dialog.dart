import 'package:flutter/material.dart';

import '../../domain/export_import.dart';
import '../../l10n/app_localizations.dart';
import '../file_transfer.dart';

/// Closes an import dialog after a successful import — only while it is
/// STILL the route on top. `mounted` alone cannot guard the follow-up pop
/// (the dialog's elements stay connected until the route is finalized),
/// and the pop would then fire on whatever route is now on top —
/// collapsing the whole route stack.
void popDialogRouteWhileCurrent(BuildContext dialogContext) {
  final route = ModalRoute.of(dialogContext);
  if (route != null && route.isCurrent) {
    Navigator.of(dialogContext).pop();
  }
}

/// Self-contained import dialog used by both the JSON and the drip CSV
/// import: a paste textarea everywhere plus a file picker where the
/// platform provides one ([canPickFile], accept list from the caller).
///
/// Owns all dialog state in its State (text controller, busy flag), so a
/// scrim dismissal while an import is running can never touch disposed
/// state afterwards. The content is small-screen safe: scrollable dialog,
/// textarea height capped at a fraction of the viewport.
final class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.applyLabel,
    required this.accept,
    required this.apply,
    required this.plan,
  });

  final String title;
  final String hint;
  final String applyLabel;

  /// HTML-style accept list forwarded to the file picker (ignored on
  /// paste-only platforms).
  final String accept;

  /// Runs the import with the dialog's own context: pops the dialog on
  /// success and reports problems itself.
  final Future<void> Function(BuildContext dialogContext, String raw) apply;

  /// Plans the import for a textarea content against the live database
  /// (counted, no writes); the dialog recomputes it as the text changes.
  final Future<ImportSummary> Function(String raw) plan;

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

final class _ImportDialogState extends State<ImportDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _running = false;

  /// True while the plan for the current textarea text is still resolving:
  /// the apply button waits for it so an import cannot preempt the
  /// overwrite warning the plan would render.
  bool _planPending = false;
  ImportSummary? _plan;
  var _planGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Rebuild on every text change so the Apply button follows both the
    // text and the busy flag.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // The plan takes async reads to resolve — dropping it here keeps the
    // warning from lingering for text the field no longer shows.
    setState(() => _plan = null);
    _recomputePlan();
  }

  /// Recomputes the overwrite plan for the current textarea content. The
  /// generation counter supersedes one plan by the next when the text is
  /// edited again before a plan's async reads resolve — a superseded plan
  /// reflects text the field no longer shows and must never render.
  Future<void> _recomputePlan() async {
    if (_running) return;
    final generation = ++_planGeneration;
    final raw = _controller.text;
    if (raw.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _plan = null;
          _planPending = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _planPending = true);
    try {
      final summary = await widget.plan(raw);
      if (!mounted || generation != _planGeneration) return;
      setState(() {
        _plan = summary;
        _planPending = false;
      });
    } catch (_) {
      // No plan to preview on any planning failure; the apply path
      // reports the problem when the user tries to import anyway.
      if (!mounted || generation != _planGeneration) return;
      setState(() {
        _plan = null;
        _planPending = false;
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final text = await pickFileText(accept: widget.accept);
    if (text != null && mounted) {
      setState(() => _controller.text = text);
    }
  }

  Future<void> _apply() async {
    final raw = _controller.text;
    setState(() => _running = true);
    try {
      await widget.apply(context, raw);
    } finally {
      // A scrim dismissal during the import disposes this State — the
      // reset must stay a silent no-op in that case.
      if (mounted) {
        setState(() => _running = false);
        // The text can change while the import runs — planning waits for it.
        _recomputePlan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final applyEnabled =
        _controller.text.trim().isNotEmpty && !_running && !_planPending;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPickFile) ...[
              OutlinedButton.icon(
                onPressed: _running ? null : _pickFile,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(AppLocalizations.of(context).importPickFile),
              ),
              const SizedBox(height: 8),
            ],
            // Height-capped expanding textarea: on small viewports
            // (keyboard up) the field shrinks to the available space.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: TextField(
                controller: _controller,
                minLines: 4,
                maxLines: null,
                decoration: InputDecoration(hintText: widget.hint),
              ),
            ),
            if ((_plan?.entriesOverwritten ?? 0) > 0)
              Text(
                AppLocalizations.of(
                  context,
                ).importOverwriteWarning(_plan!.entriesOverwritten),
                key: const ValueKey('importOverwritePreview'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          // Cancel stays enabled while running — a scrim tap is equally
          // possible, so gating only this button would be a pretense.
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: applyEnabled ? _apply : null,
          child: Text(widget.applyLabel),
        ),
      ],
    );
  }
}
