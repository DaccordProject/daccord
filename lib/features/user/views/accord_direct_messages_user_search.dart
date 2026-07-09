part of 'accord_direct_messages.dart';

/// The shared user-search core of the DM dialogs: the query field + search
/// button, the `searchUsers` call, and the results list (with its empty
/// state). The hosting dialog owns the busy flag — the search toggles it via
/// [onBusyChanged] so a running search and dialog-level actions disable each
/// other — and renders each result via [tileBuilder], which is what
/// distinguishes the create-group (checkbox multi-select), pick-user
/// (tap-to-pick) and add-friend (send-request button) dialogs. [belowSearch]
/// slots dialog-specific widgets (selection chips, status text) between the
/// search row and the results; [excludeIds] hides users already present.
///
/// Must be given a bounded height (e.g. wrapped in a `Flexible` inside the
/// dialog's column) so the results list can shrink when space is tight.
class _UserSearchList extends ConsumerStatefulWidget {
  const _UserSearchList({
    required this.hintText,
    required this.busy,
    required this.onBusyChanged,
    required this.tileBuilder,
    this.excludeIds = const <String>{},
    this.belowSearch = const <Widget>[],
  });

  final String hintText;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final Widget Function(AccordUser user) tileBuilder;
  final Set<String> excludeIds;
  final List<Widget> belowSearch;

  @override
  ConsumerState<_UserSearchList> createState() => _UserSearchListState();
}

class _UserSearchListState extends ConsumerState<_UserSearchList> {
  final _query = TextEditingController();
  List<AccordUser>? _results;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final client = ref.accordClient;
    final query = _query.text.trim();
    if (client == null || query.isEmpty) return;
    widget.onBusyChanged(true);
    final result = await client.users.searchUsers(query);
    if (!mounted) return;
    widget.onBusyChanged(false);
    final data = result.data;
    setState(() {
      _results = data is List
          ? data
                .whereType<AccordUser>()
                .where((u) => !widget.excludeIds.contains(u.id))
                .toList()
          : <AccordUser>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                enabled: !widget.busy,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.hintText,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: widget.busy ? null : _search,
              child: const Text('Search'),
            ),
          ],
        ),
        ...widget.belowSearch,
        const SizedBox(height: 8),
        Flexible(
          child: results == null
              ? const SizedBox.shrink()
              : results.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No users found',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final user in results) widget.tileBuilder(user),
                  ],
                ),
        ),
      ],
    );
  }
}
