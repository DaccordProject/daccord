import 'package:accordkit/accordkit.dart';
import 'package:flutter/widgets.dart';

/// Shared state machine for dialogs that load a list once when opened.
///
/// Consolidates the `_list?/_loading/_error/_load()` boilerplate that the
/// moderation dialogs (ban list, invites, soundboard) each re-typed: the mixin
/// owns the [items]/[loading]/[error] trio and the load flow (kicked off from
/// `initState`), while each screen supplies [fetchItems] and keeps its own
/// loading/error/empty rendering.
mixin SelfLoadingListState<T, W extends StatefulWidget> on State<W> {
  /// The loaded items; null until the first [load] completes, so screens can
  /// key their initial-loading UI off null-ness.
  List<T>? items;

  /// True while [load] is in flight. Screens that share one busy flag between
  /// loading and mutations may also toggle this around their own writes.
  bool loading = false;

  /// The last load (or mutation) error, if any. Cleared when a load starts.
  String? error;

  /// Whether a load may start (e.g. a client is available). When false,
  /// [load] returns without touching any state.
  bool get canLoad => true;

  /// Fetches and parses the list. Returns the new items (null = keep the
  /// current list) and an error message (null = success).
  Future<(List<T>? items, String? error)> fetchItems();

  @override
  void initState() {
    super.initState();
    load();
  }

  /// Runs [fetchItems] and applies the result; safe to re-invoke (refresh).
  Future<void> load() async {
    if (!canLoad) return;
    setState(() {
      loading = true;
      error = null;
    });
    final (newItems, newError) = await fetchItems();
    if (!mounted) return;
    setState(() {
      loading = false;
      if (newItems != null) items = newItems;
      error = newError;
    });
  }
}

/// [SelfLoadingListState]'s sibling for `before`-cursor paginated dialogs
/// (reports, audit log): a stable [items] list plus the
/// [hasMore]/[loadingMore]/[loadMore] flow with id-based de-duplication.
///
/// Cursor semantics: the [itemId] of the last item is sent as `before` on
/// continuation pages; a short page (fewer than [pageSize] items) or a page of
/// only already-known ids ends pagination.
mixin PaginatedListState<T, W extends StatefulWidget> on State<W> {
  /// The loaded items. Non-null from construction so live gateway events can
  /// prepend entries even before (or after a failed) initial load.
  final List<T> items = [];

  /// True while the initial [load] (or a filter-change reload) is in flight.
  bool loading = true;

  /// True while a [loadMore] continuation page is in flight.
  bool loadingMore = false;

  /// Whether another page may exist (drives the "Load more" sentinel row).
  bool hasMore = true;

  /// The last load error, if any. Cleared when a full [load] starts.
  String? error;

  /// Page size requested per fetch; a shorter page ends pagination.
  int get pageSize;

  /// Whether a load may start (e.g. a client is available). When false,
  /// [load]/[loadMore] return without touching any state.
  bool get canLoad => true;

  /// The id used as the `before` cursor and for de-duplication. Returning
  /// null for the last item stops pagination (no usable cursor).
  String? itemId(T item);

  /// Fetches one page, with [before] set on continuation pages.
  Future<RestResult> fetchPage({String? before});

  /// Parses the raw page payload into items.
  List<T> parseItems(Object? data);

  /// The error message for a failed initial load.
  String loadError(RestResult result);

  /// The error message for a failed continuation page.
  String loadMoreError(RestResult result);

  @override
  void initState() {
    super.initState();
    load();
  }

  /// (Re)loads the first page, replacing [items]; safe to re-invoke (refresh
  /// or filter change).
  Future<void> load() async {
    if (!canLoad) return;
    setState(() {
      loading = true;
      error = null;
    });
    final result = await fetchPage();
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        loading = false;
        error = loadError(result);
      });
      return;
    }
    final parsed = parseItems(result.data);
    setState(() {
      loading = false;
      items
        ..clear()
        ..addAll(parsed);
      hasMore = parsed.length >= pageSize;
    });
  }

  /// Fetches the page before the last item and appends any unseen entries.
  Future<void> loadMore() async {
    if (!canLoad || loadingMore || !hasMore || items.isEmpty) return;
    final before = itemId(items.last);
    if (before == null) return;
    setState(() => loadingMore = true);
    final result = await fetchPage(before: before);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        loadingMore = false;
        error = loadMoreError(result);
      });
      return;
    }
    final parsed = parseItems(result.data);
    final existing = items.map(itemId).toSet();
    final fresh = parsed.where((e) => !existing.contains(itemId(e))).toList();
    setState(() {
      loadingMore = false;
      items.addAll(fresh);
      hasMore = parsed.length >= pageSize && fresh.isNotEmpty;
    });
  }
}
