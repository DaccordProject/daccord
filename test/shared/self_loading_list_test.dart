import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/self_loading_list.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal host for [SelfLoadingListState], stripped of any real screen UI so
/// the load flow can be driven and inspected directly through the state
/// reached via [key]. [results] is a queue the test seeds *before* pumping
/// (since `initState` fires the first [SelfLoadingListState.load] call
/// synchronously) and can keep appending to for subsequent loads.
class _SelfLoadingHost extends StatefulWidget {
  const _SelfLoadingHost({
    super.key,
    required this.results,
    this.canLoad = true,
  });

  final List<(List<int>?, String?)> results;
  final bool canLoad;

  @override
  State<_SelfLoadingHost> createState() => _SelfLoadingHostState();
}

class _SelfLoadingHostState extends State<_SelfLoadingHost>
    with SelfLoadingListState<int, _SelfLoadingHost> {
  int fetchCount = 0;

  @override
  bool get canLoad => widget.canLoad;

  @override
  Future<(List<int>?, String?)> fetchItems() async {
    fetchCount++;
    return widget.results.removeAt(0);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Minimal host for [PaginatedListState], with pages supplied per-call so
/// pagination/cursor/de-dup behaviour can be asserted directly. [pages] must
/// hold the first page *before* pumping for the same reason as above.
class _PaginatedHost extends StatefulWidget {
  const _PaginatedHost({super.key, required this.pages, this.pageSize = 2});

  final List<List<int>?> pages;
  final int pageSize;

  @override
  State<_PaginatedHost> createState() => _PaginatedHostState();
}

class _PaginatedHostState extends State<_PaginatedHost>
    with PaginatedListState<int, _PaginatedHost> {
  final beforeArgs = <String?>[];

  @override
  int get pageSize => widget.pageSize;

  @override
  String? itemId(int item) => item.toString();

  @override
  Future<RestResult> fetchPage({String? before}) async {
    beforeArgs.add(before);
    final page = widget.pages.removeAt(0);
    if (page == null) {
      return RestResult(ok: false, statusCode: 500);
    }
    return RestResult.success(200, page);
  }

  @override
  List<int> parseItems(Object? data) => (data as List).cast<int>();

  @override
  String loadError(RestResult result) => 'load failed';

  @override
  String loadMoreError(RestResult result) => 'load more failed';

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('SelfLoadingListState', () {
    testWidgets('loads items automatically on initState', (tester) async {
      final key = GlobalKey<_SelfLoadingHostState>();
      final results = <(List<int>?, String?)>[
        (const [1, 2, 3], null),
      ];
      await tester.pumpWidget(_SelfLoadingHost(key: key, results: results));
      await tester.pump();

      expect(key.currentState!.items, [1, 2, 3]);
      expect(key.currentState!.loading, isFalse);
      expect(key.currentState!.error, isNull);
      expect(key.currentState!.fetchCount, 1);
    });

    testWidgets('a failed load keeps items null and records the error', (
      tester,
    ) async {
      final key = GlobalKey<_SelfLoadingHostState>();
      final results = <(List<int>?, String?)>[(null, 'boom')];
      await tester.pumpWidget(_SelfLoadingHost(key: key, results: results));
      await tester.pump();

      expect(key.currentState!.items, isNull);
      expect(key.currentState!.loading, isFalse);
      expect(key.currentState!.error, 'boom');
    });

    testWidgets(
      'a refresh keeps the previous items when the new page is null',
      (tester) async {
        final key = GlobalKey<_SelfLoadingHostState>();
        final results = <(List<int>?, String?)>[
          (const [1], null),
          (null, null),
        ];
        await tester.pumpWidget(_SelfLoadingHost(key: key, results: results));
        await tester.pump();
        expect(key.currentState!.items, [1]);

        await key.currentState!.load();
        expect(key.currentState!.items, [1]);
      },
    );

    testWidgets('canLoad=false skips the fetch entirely', (tester) async {
      final key = GlobalKey<_SelfLoadingHostState>();
      final results = <(List<int>?, String?)>[];
      await tester.pumpWidget(
        _SelfLoadingHost(key: key, results: results, canLoad: false),
      );
      await tester.pump();

      expect(key.currentState!.fetchCount, 0);
      expect(key.currentState!.loading, isFalse);
      expect(key.currentState!.items, isNull);
    });
  });

  group('PaginatedListState', () {
    testWidgets('load() replaces items and sets hasMore from the page size', (
      tester,
    ) async {
      final key = GlobalKey<_PaginatedHostState>();
      final pages = <List<int>?>[
        [1, 2],
      ];
      await tester.pumpWidget(
        _PaginatedHost(key: key, pages: pages, pageSize: 2),
      );
      await tester.pump();

      expect(key.currentState!.items, [1, 2]);
      expect(key.currentState!.hasMore, isTrue);
      expect(key.currentState!.loading, isFalse);
    });

    testWidgets('a short first page reports no more pages', (tester) async {
      final key = GlobalKey<_PaginatedHostState>();
      final pages = <List<int>?>[
        [1],
      ];
      await tester.pumpWidget(
        _PaginatedHost(key: key, pages: pages, pageSize: 2),
      );
      await tester.pump();

      expect(key.currentState!.items, [1]);
      expect(key.currentState!.hasMore, isFalse);
    });

    testWidgets('loadMore appends fresh items and dedupes known ids', (
      tester,
    ) async {
      final key = GlobalKey<_PaginatedHostState>();
      final pages = <List<int>?>[
        [1, 2],
      ];
      await tester.pumpWidget(
        _PaginatedHost(key: key, pages: pages, pageSize: 2),
      );
      await tester.pump();
      expect(key.currentState!.items, [1, 2]);

      // Continuation page re-sends the last known id (2) plus one new id (3);
      // the server-side cursor overlap must not duplicate 2.
      pages.add([2, 3]);
      await key.currentState!.loadMore();

      expect(key.currentState!.items, [1, 2, 3]);
      expect(key.currentState!.beforeArgs.last, '2');
      expect(key.currentState!.hasMore, isTrue);
    });

    testWidgets('loadMore ends pagination on a short continuation page', (
      tester,
    ) async {
      final key = GlobalKey<_PaginatedHostState>();
      final pages = <List<int>?>[
        [1, 2],
      ];
      await tester.pumpWidget(
        _PaginatedHost(key: key, pages: pages, pageSize: 2),
      );
      await tester.pump();

      pages.add([3]);
      await key.currentState!.loadMore();

      expect(key.currentState!.items, [1, 2, 3]);
      expect(key.currentState!.hasMore, isFalse);
    });

    testWidgets('loadMore is a no-op once hasMore is false', (tester) async {
      final key = GlobalKey<_PaginatedHostState>();
      final pages = <List<int>?>[
        [1],
      ];
      await tester.pumpWidget(
        _PaginatedHost(key: key, pages: pages, pageSize: 2),
      );
      await tester.pump();
      expect(key.currentState!.hasMore, isFalse);

      await key.currentState!.loadMore();
      expect(pages, isEmpty); // fetchPage was never called
      expect(key.currentState!.items, [1]);
    });

    testWidgets('a failed loadMore surfaces the error and stops loadingMore', (
      tester,
    ) async {
      final key = GlobalKey<_PaginatedHostState>();
      final pages = <List<int>?>[
        [1, 2],
      ];
      await tester.pumpWidget(
        _PaginatedHost(key: key, pages: pages, pageSize: 2),
      );
      await tester.pump();

      pages.add(null);
      await key.currentState!.loadMore();

      expect(key.currentState!.error, 'load more failed');
      expect(key.currentState!.loadingMore, isFalse);
      expect(key.currentState!.items, [1, 2]);
    });
  });
}
