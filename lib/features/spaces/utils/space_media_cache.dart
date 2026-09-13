import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';

final spaceMediaCache = SpaceMediaCache();

/// Stable server media paths need both eviction and a new provider key: an
/// already mounted Image otherwise keeps its old image stream after a rebuild.
class SpaceMediaCache {
  SpaceMediaCache({Future<void> Function(String)? evict})
    : _evict = evict ?? _evictImage;

  final Future<void> Function(String) _evict;
  final Map<String, int> _revisions = {};
  int _revision = DateTime.now().microsecondsSinceEpoch;

  String resolve(String url) {
    final revision = _revisions[url];
    if (revision == null) return url;
    final uri = Uri.parse(url);
    return uri
        .replace(
          query:
              '${uri.hasQuery ? '${uri.query}&' : ''}'
              '_daccord_media=$revision',
        )
        .toString();
  }

  Future<void> invalidate(Iterable<String> urls) async {
    for (final url in urls.toSet()) {
      final old = resolve(url);
      // Publish the revision before any asynchronous cache work; another
      // rebuild cannot resolve the stale key while disk eviction is pending.
      _revisions[url] = ++_revision;
      for (final cachedUrl in {url, old}) {
        try {
          await _evict(cachedUrl);
        } catch (error) {
          // A disk-cache failure must not turn an accepted save into a failure.
          // The new provider/HTTP key still fetches fresh bytes.
          debugPrint('Could not evict updated space media: $error');
        }
      }
    }
  }

  static Future<void> _evictImage(String url) async {
    // evictFromCache removes this URL from both disk and Flutter's image cache.
    await CachedNetworkImage.evictFromCache(url);
  }
}
