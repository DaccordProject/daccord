import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:flutter/material.dart';

/// Live registry of the widgets the first-launch tour can spotlight (#175).
///
/// A plain global (mirroring `mcpHomeBridge`) rather than a Riverpod provider on
/// purpose: registration happens in `initState`/`dispose` of widgets deep inside
/// other features, and mutating provider state from there would fight the build
/// cycle for something that is pure, throwaway view geometry.
///
/// Anchors are *opt-in*: a feature wraps the widget it is happy to have pointed
/// at in an [OnboardingAnchor] and nothing else changes. Ids with no registered
/// widget simply don't resolve, and the tour falls back (see
/// [resolveOnboardingAnchorRect]).
class OnboardingAnchorRegistry {
  final Map<OnboardingAnchorId, List<GlobalKey>> _keys =
      <OnboardingAnchorId, List<GlobalKey>>{};

  /// Publishes [key] as a candidate for [id]. Several widgets may claim the same
  /// id (e.g. the rail is built once inline and once inside the mobile drawer);
  /// resolution picks whichever is actually on screen.
  void register(OnboardingAnchorId id, GlobalKey key) {
    (_keys[id] ??= <GlobalKey>[]).add(key);
  }

  void unregister(OnboardingAnchorId id, GlobalKey key) {
    final list = _keys[id];
    if (list == null) return;
    list.remove(key);
    if (list.isEmpty) _keys.remove(id);
  }

  /// Every candidate key for [id], most recently registered last.
  List<GlobalKey> keysFor(OnboardingAnchorId id) =>
      _keys[id] ?? const <GlobalKey>[];

  bool get isEmpty => _keys.isEmpty;

  @visibleForTesting
  void clear() => _keys.clear();
}

/// The app-wide anchor registry.
final OnboardingAnchorRegistry onboardingAnchors = OnboardingAnchorRegistry();

/// Marks [child] as the on-screen representative of [anchor] for the duration of
/// its life. Purely a registration wrapper — it adds no padding, no repaint
/// boundary and no rebuild; the child's layout is untouched.
///
/// ```dart
/// OnboardingAnchor(
///   anchor: OnboardingAnchorId.spaceRail,
///   child: _SpaceRail(...),
/// )
/// ```
class OnboardingAnchor extends StatefulWidget {
  const OnboardingAnchor({
    super.key,
    required this.anchor,
    required this.child,
  });

  final OnboardingAnchorId anchor;
  final Widget child;

  @override
  State<OnboardingAnchor> createState() => _OnboardingAnchorState();
}

class _OnboardingAnchorState extends State<OnboardingAnchor> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    onboardingAnchors.register(widget.anchor, _key);
  }

  @override
  void didUpdateWidget(covariant OnboardingAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchor != widget.anchor) {
      onboardingAnchors
        ..unregister(oldWidget.anchor, _key)
        ..register(widget.anchor, _key);
    }
  }

  @override
  void dispose() {
    onboardingAnchors.unregister(widget.anchor, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// Widget type names probed for when an id has no registered [OnboardingAnchor].
///
/// This is a **fallback**, not the mechanism: the tour is meant to be anchored
/// by feature modules opting in. Until those one-line wraps land (they live in
/// files this module deliberately does not edit), matching on the private widget
/// type name keeps the walkthrough pointed at the real UI instead of degrading
/// to a stack of centred cards. Names are compared as strings so nothing here
/// has to import — or be able to see — another feature's private classes.
///
/// Safe by construction: a miss just means "no rect", which the tour already
/// handles. Delete an entry the moment its surface registers a real anchor.
const Map<OnboardingAnchorId, List<String>> kOnboardingAnchorTypeProbes =
    <OnboardingAnchorId, List<String>>{
      // spaceRail, channelList, navMenu and voiceChannel now register real
      // OnboardingAnchors at their surfaces, so their probes are gone.
      OnboardingAnchorId.messageComposer: <String>['_Composer'],
      OnboardingAnchorId.messageList: <String>['MessagePane'],
    };

/// Tooltip text identifying the mobile drawer button, which is a bare
/// [IconButton] with no type of its own to match on.
const String kOnboardingNavMenuTooltip = 'Channels';

/// The rectangle to spotlight for [id], in [overlay]'s coordinate space, or null
/// when nothing suitable is on screen.
///
/// Resolution order:
///   1. a registered [OnboardingAnchor] whose render box is attached, laid out
///      and visible inside [overlay];
///   2. the widget-type probe above, searched from [searchRoot];
///   3. null — the caller centres its card instead.
Rect? resolveOnboardingAnchorRect(
  OnboardingAnchorId id, {
  required RenderBox overlay,
  BuildContext? searchRoot,
}) {
  // Registration order, so an id claimed by a repeated widget (every voice
  // channel row, say) spotlights the first one rather than an arbitrary one.
  for (final key in onboardingAnchors.keysFor(id)) {
    final rect = _rectOf(key.currentContext, overlay);
    if (rect != null) return rect;
  }
  if (searchRoot == null) return null;
  final element = _probe(id, searchRoot);
  return element == null ? null : _rectOf(element, overlay);
}

/// The first of [ids] that resolves, in priority order.
Rect? resolveFirstOnboardingAnchorRect(
  List<OnboardingAnchorId> ids, {
  required RenderBox overlay,
  BuildContext? searchRoot,
}) {
  for (final id in ids) {
    final rect = resolveOnboardingAnchorRect(
      id,
      overlay: overlay,
      searchRoot: searchRoot,
    );
    if (rect != null) return rect;
  }
  return null;
}

/// Geometry of [context]'s render box relative to [overlay], or null when it is
/// unmounted, not laid out, zero-sized, or scrolled/clipped out of view.
Rect? _rectOf(BuildContext? context, RenderBox overlay) {
  if (context == null || !context.mounted) return null;
  final object = context.findRenderObject();
  if (object is! RenderBox) return null;
  if (!object.attached || !object.hasSize) return null;
  if (!overlay.attached || !overlay.hasSize) return null;
  final size = object.size;
  if (size.width < 1 || size.height < 1) return null;
  final Rect rect;
  try {
    rect = MatrixUtils.transformRect(
      object.getTransformTo(overlay),
      Offset.zero & size,
    );
  } catch (_) {
    // getTransformTo throws when the two render objects don't share an
    // ancestor (a route that has just been popped, say). Treat as "not here".
    return null;
  }
  if (!rect.isFinite) return null;
  final visible = rect.intersect(Offset.zero & overlay.size);
  // Require a meaningful sliver to be on screen — a 1px edge of a drawer that
  // is mid-animation is not something worth spotlighting.
  if (visible.width < 8 || visible.height < 8) return null;
  return visible;
}

/// Depth-first search for the first element matching [id]'s probe. Bounded so a
/// pathological tree can't stall a frame.
Element? _probe(OnboardingAnchorId id, BuildContext searchRoot) {
  final names = kOnboardingAnchorTypeProbes[id];
  if (names == null && id != OnboardingAnchorId.navMenu) return null;
  if (!searchRoot.mounted) return null;

  bool matches(Widget widget) {
    if (id == OnboardingAnchorId.navMenu) {
      return widget is IconButton &&
          widget.tooltip == kOnboardingNavMenuTooltip;
    }
    return names!.contains(widget.runtimeType.toString());
  }

  Element? found;
  var visited = 0;
  void visit(Element element) {
    if (found != null || visited++ > 20000) return;
    if (matches(element.widget)) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  try {
    (searchRoot as Element).visitChildren(visit);
  } catch (_) {
    return null;
  }
  return found;
}
