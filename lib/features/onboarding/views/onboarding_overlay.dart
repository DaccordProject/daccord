import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/onboarding/views/onboarding_anchors.dart';
import 'package:bonfire/features/onboarding/views/onboarding_help.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Gap between the spotlit rectangle and the callout card.
const double kOnboardingCalloutGap = 16;

/// Minimum distance the card keeps from the edge of the screen.
const double kOnboardingCalloutMargin = 16;

/// Preferred card width; narrowed on phones by the layout delegate.
const double kOnboardingCalloutWidth = 360;

/// How far the spotlight is inflated past the anchor's own bounds.
const double kOnboardingSpotlightPadding = 6;

/// Where to put a [card] of the given size inside an [overlay], given the
/// rectangle being spotlit.
///
/// Pure so the placement rules can be unit-tested without pumping a frame.
/// Preference order — below the target, above it, to its right, to its left,
/// then dead centre — is what keeps the card off a full-height target like the
/// space rail (nothing fits above or below it, so the card lands beside it)
/// while still sitting directly under a small one like the mobile menu button.
Offset onboardingCalloutOffset({
  required Size overlay,
  required Size card,
  Rect? target,
  double gap = kOnboardingCalloutGap,
  double margin = kOnboardingCalloutMargin,
}) {
  double clampX(double x) => _clamp(x, margin, overlay.width - card.width - margin);
  double clampY(double y) =>
      _clamp(y, margin, overlay.height - card.height - margin);

  if (target == null || target.isEmpty) {
    return Offset(
      (overlay.width - card.width) / 2,
      (overlay.height - card.height) / 2,
    );
  }

  final centredX = clampX(target.center.dx - card.width / 2);
  final centredY = clampY(target.center.dy - card.height / 2);

  // Below.
  final below = target.bottom + gap;
  if (below + card.height <= overlay.height - margin) {
    return Offset(centredX, below);
  }
  // Above.
  final above = target.top - gap - card.height;
  if (above >= margin) return Offset(centredX, above);
  // Right.
  final right = target.right + gap;
  if (right + card.width <= overlay.width - margin) {
    return Offset(right, centredY);
  }
  // Left.
  final left = target.left - gap - card.width;
  if (left >= margin) return Offset(left, centredY);
  // Nothing fits alongside it — centre, and let the scrim's cut-out carry the
  // "this thing" signal on its own.
  return Offset(
    (overlay.width - card.width) / 2,
    (overlay.height - card.height) / 2,
  );
}

double _clamp(double value, double min, double max) {
  if (max < min) return min;
  return value < min ? min : (value > max ? max : value);
}

/// The first-launch walkthrough (#175): a scrim with a hole punched over the
/// real widget being described, plus a card explaining it.
///
/// Owns nothing persistent — the "seen" marker and the decision to show at all
/// live in `OnboardingController`. That split is what lets this be pumped
/// directly in a widget test with a hand-made step list.
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    this.searchRoot,
    this.onHelp,
  });

  /// The cards to walk through, in order. Must not be empty.
  final List<OnboardingStep> steps;

  /// Called once when the tour ends, with true when the user reached the last
  /// step and false when they skipped or backed out. Either way the caller is
  /// expected to stamp the seen-marker: a skip is still an answer.
  final void Function(bool completed) onFinish;

  /// Root for the widget-type anchor fallback (see
  /// [resolveOnboardingAnchorRect]). Defaults to the root navigator's context.
  final BuildContext? searchRoot;

  /// Overrides the help action, for tests. Defaults to
  /// [showOnboardingHelpDialog].
  final VoidCallback? onHelp;

  @override
  State<OnboardingOverlay> createState() => OnboardingOverlayState();
}

class OnboardingOverlayState extends State<OnboardingOverlay>
    with WidgetsBindingObserver {
  int _index = 0;
  Rect? _target;
  bool _finished = false;

  /// The step currently on screen.
  OnboardingStep get step => widget.steps[_index];

  /// Zero-based index of the step on screen.
  int get index => _index;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleResolve();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A window resize / rotation / keyboard can move every anchor.
  @override
  void didChangeMetrics() => _scheduleResolve();

  /// Anchors are resolved *after* layout, never during build: the pane being
  /// pointed at lives in a different subtree (often a route below this one) and
  /// may not have been laid out yet on the frame this overlay first appears.
  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolve();
    });
  }

  void _resolve() {
    final overlay = context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) return;
    final rect = resolveFirstOnboardingAnchorRect(
      step.anchors,
      overlay: overlay,
      searchRoot: widget.searchRoot ?? context,
    );
    if (rect != _target) setState(() => _target = rect);
  }

  void _goTo(int next) {
    if (next < 0 || next >= widget.steps.length) return;
    setState(() {
      _index = next;
      // Drop the old cut-out immediately so a stale hole never sits over the
      // new step's text for a frame.
      _target = null;
    });
    _scheduleResolve();
  }

  void next() {
    if (_index == widget.steps.length - 1) {
      _finish(true);
    } else {
      _goTo(_index + 1);
    }
  }

  void back() => _goTo(_index - 1);

  void skip() => _finish(false);

  void _finish(bool completed) {
    if (_finished) return;
    _finished = true;
    widget.onFinish(completed);
  }

  void _help() {
    final override = widget.onHelp;
    if (override != null) {
      override();
      return;
    }
    showOnboardingHelpDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final target = _target;
    final spotlight = target?.inflate(kOnboardingSpotlightPadding);

    return Semantics(
      container: true,
      label: 'Daccord tour, step ${_index + 1} of ${widget.steps.length}',
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Scrim + cut-out. Tapping anywhere off the card advances, which is
            // what makes this feel like a tour rather than a modal quiz — and
            // tapping the highlighted widget itself is the natural "yes, that
            // one" gesture.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: next,
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    spotlight: spotlight,
                    scrim: Colors.black.withValues(alpha: 0.72),
                    border: colors.primary,
                  ),
                ),
              ),
            ),
            CustomSingleChildLayout(
              delegate: _CalloutLayoutDelegate(spotlight),
              child: _OnboardingCard(
                step: step,
                index: _index,
                total: widget.steps.length,
                onNext: next,
                onBack: _index == 0 ? null : back,
                onSkip: skip,
                onHelp: _help,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fills the screen with [scrim] and punches a rounded hole at [spotlight].
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.spotlight,
    required this.scrim,
    required this.border,
  });

  final Rect? spotlight;
  final Color scrim;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final hole = spotlight;
    if (hole == null || hole.isEmpty) {
      canvas.drawRect(full, Paint()..color = scrim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(10));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRRect(rrect),
      ),
      Paint()..color = scrim,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.spotlight != spotlight ||
      oldDelegate.scrim != scrim ||
      oldDelegate.border != border;
}

/// Sizes the card and hands its position to [onboardingCalloutOffset].
class _CalloutLayoutDelegate extends SingleChildLayoutDelegate {
  const _CalloutLayoutDelegate(this.target);

  final Rect? target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    const inset = kOnboardingCalloutMargin * 2;
    return BoxConstraints(
      maxWidth: constraints.maxWidth - inset < kOnboardingCalloutWidth
          ? (constraints.maxWidth - inset).clamp(0.0, kOnboardingCalloutWidth)
          : kOnboardingCalloutWidth,
      maxHeight: (constraints.maxHeight - inset).clamp(
        0.0,
        constraints.maxHeight,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      onboardingCalloutOffset(overlay: size, card: childSize, target: target);

  @override
  bool shouldRelayout(_CalloutLayoutDelegate oldDelegate) =>
      oldDelegate.target != target;
}

/// The explanatory card: title, body, progress and the controls.
class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
    required this.onHelp,
  });

  final OnboardingStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final isLast = index == total - 1;

    return Material(
      color: colors.foreground,
      elevation: 12,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(step.icon, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        step.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.dirtyWhite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Help & support',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.help_outline, color: colors.gray),
                    onPressed: onHelp,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  step.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.gray,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _StepDots(index: index, total: total),
              const SizedBox(height: 4),
              // A Wrap, not a Row: six dots plus Skip/Back/Next already overflow
              // a 360pt card, and the UI-scale setting can double every label.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (!isLast)
                    TextButton(
                      onPressed: onSkip,
                      child: Text(
                        'Skip',
                        style: TextStyle(color: colors.gray),
                      ),
                    ),
                  if (onBack != null)
                    TextButton(
                      onPressed: onBack,
                      child: Text(
                        'Back',
                        style: TextStyle(color: colors.dirtyWhite),
                      ),
                    ),
                  FilledButton(
                    onPressed: onNext,
                    child: Text(isLast ? 'Done' : 'Next'),
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

class _StepDots extends StatelessWidget {
  const _StepDots({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Semantics(
      label: 'Step ${index + 1} of $total',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == index ? colors.primary : colors.darkGray,
              ),
            ),
        ],
      ),
    );
  }
}
