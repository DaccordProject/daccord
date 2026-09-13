import 'package:bonfire/features/spaces/utils/space_media_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'replacing a stable URL repeatedly changes its key and evicts only that asset',
    () async {
      final evicted = <String>[];
      final cache = SpaceMediaCache(evict: (url) async => evicted.add(url));
      const icon = 'https://one.test/cdn/icons/s.png';
      const otherIcon = 'https://two.test/cdn/icons/s.png';
      const banner = 'https://one.test/cdn/banners/s.png';
      expect(cache.resolve(icon), icon);
      await cache.invalidate([icon, icon]);
      final first = cache.resolve(icon);
      expect(first, isNot(icon));
      expect(evicted, [icon]);
      await cache.invalidate([icon]);
      expect(cache.resolve(icon), isNot(first));
      expect(evicted, [icon, icon, first]);
      expect(cache.resolve(otherIcon), otherIcon);
      expect(cache.resolve(banner), banner);
    },
  );

  test('revision preserves existing query parameters and fragments', () async {
    final cache = SpaceMediaCache(evict: (_) async {});
    const url = 'https://one.test/icon.png?size=128&x=a%20b#asset';
    await cache.invalidate([url]);
    final refreshed = Uri.parse(cache.resolve(url));
    expect(refreshed.queryParameters['size'], '128');
    expect(refreshed.queryParameters['x'], 'a b');
    expect(refreshed.fragment, 'asset');
    expect(refreshed.queryParameters['_daccord_media'], isNotEmpty);
  });

  test('failed disk eviction still refreshes the accepted update', () async {
    final cache = SpaceMediaCache(
      evict: (_) async => throw StateError('disk unavailable'),
    );
    const url = 'https://one.test/icon.png';
    await cache.invalidate([url]);
    expect(cache.resolve(url), isNot(url));
  });
}
