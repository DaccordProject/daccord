import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/utils/emoticons.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Performs a post composer's submit with the trimmed [title]/[body]. Returns
/// the error text to display in the dialog, or null on success — in which case
/// the callback is responsible for popping the dialog with its result.
typedef PostComposerSubmit = Future<String?> Function(
    AccordClient client, String title, String body);

/// The shared title+body composer dialog behind the forum's "New post" and the
/// thread view's post/reply editor. [title] is the dialog heading;
/// [initialTitle] seeds the title field, or hides it entirely when null
/// (body-only reply editing). The title is validated manually ("Title is
/// required") so the error shows in the dialog's error slot, matching the
/// original dialogs. While [onSubmit] runs the fields and buttons are
/// disabled; a returned error re-enables them and is shown above the actions.
class PostComposerDialog extends ConsumerStatefulWidget {
  const PostComposerDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.bodyLabel,
    required this.onSubmit,
    this.initialTitle,
    this.initialBody = '',
    this.autofocusTitle = false,
  });

  final String title;
  final String submitLabel;
  final String bodyLabel;
  final PostComposerSubmit onSubmit;

  /// Initial text for the title field, or null to omit the field (and its
  /// required-validation) entirely.
  final String? initialTitle;
  final String initialBody;
  final bool autofocusTitle;

  @override
  ConsumerState<PostComposerDialog> createState() =>
      _PostComposerDialogState();
}

class _PostComposerDialogState extends ConsumerState<PostComposerDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody);
  bool _busy = false;
  String? _error;

  bool get _hasTitleField => widget.initialTitle != null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final rawBody = _body.text.trim();
    // Bodies convert emoticons like every other send path. Titles deliberately
    // don't: they're short plain-text labels, not markdown.
    final body =
        ref.read(settingsControllerProvider.select((s) => s.convertEmoticons))
        ? applyEmoticons(rawBody)
        : rawBody;
    if (_hasTitleField && title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    final client = ref.read(accordAuthProvider
        .select((s) => s is AccordAuthLoggedIn ? s.client : null));
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(client, title, body);
    // On success the callback popped the dialog; leave the busy state as-is.
    if (!mounted || error == null) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              if (_hasTitleField) ...[
                TextField(
                  controller: _title,
                  autofocus: widget.autofocusTitle,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _body,
                autofocus: !_hasTitleField,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: widget.bodyLabel,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(widget.submitLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
