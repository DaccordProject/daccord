import 'package:bonfire/features/onboarding/models/onboarding_step.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/models/home_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The width the message column actually gets under [layout] at [width].
double _messagePaneWidth(HomeLayout layout, double width) {
  if (layout.mode == HomeLayoutMode.compact) return width;
  return width -
      kSpaceRailWidth -
      layout.channelListWidth -
      kChannelListHandleWidth -
      (layout.showsMemberListInline ? kMemberListWidth : 0);
}

HomeLayout _at(
  double width, {
  double channelListWidth = AccordSettings.defaultChannelListWidth,
}) => resolveHomeLayout(
  width: width,
  preferredChannelListWidth: channelListWidth,
);

void main() {
  group('resolveHomeLayout at the viewports App Review used (#292)', () {
    test('iPad Air landscape (1180) keeps all three panes', () {
      final layout = _at(1180);
      expect(layout.mode, HomeLayoutMode.wide);
      expect(layout.channelListWidth, AccordSettings.defaultChannelListWidth);
      expect(_messagePaneWidth(layout, 1180), greaterThan(600));
    });

    test('iPad Air portrait (820) drops the member list, not the channels', () {
      final layout = _at(820);
      expect(layout.mode, HomeLayoutMode.medium);
      expect(layout.showsSidebarInline, isTrue);
      expect(layout.showsMemberListInline, isFalse);
      // The regression: three panes at 820 left the message column (~280)
      // narrower than the member list it sat next to.
      expect(_messagePaneWidth(layout, 820), greaterThan(kMemberListWidth));
    });

    test('iPad 1024x768 landscape keeps all three panes', () {
      expect(_at(1024).mode, HomeLayoutMode.wide);
    });

    test('iPad 1024x768 portrait (768) drops the member list', () {
      final layout = _at(768);
      expect(layout.mode, HomeLayoutMode.medium);
      expect(_messagePaneWidth(layout, 768), greaterThan(kMemberListWidth));
    });

    test('phone (393) uses the drawer layout', () {
      expect(_at(393).mode, HomeLayoutMode.compact);
    });
  });

  group('the message column never falls below its minimum', () {
    test('across every width that keeps a pane inline', () {
      for (var width = kHomeSidebarBreakpoint; width <= 2000; width += 1) {
        for (final preferred in <double>[
          AccordSettings.minChannelListWidth,
          AccordSettings.defaultChannelListWidth,
          AccordSettings.maxChannelListWidth,
        ]) {
          final layout = _at(width, channelListWidth: preferred);
          expect(
            _messagePaneWidth(layout, width),
            greaterThanOrEqualTo(kMinMessagePaneWidth),
            reason: 'width=$width preferredChannelList=$preferred',
          );
        }
      }
    });
  });

  group('panes are given up in order', () {
    test('the member list goes before the channel list', () {
      expect(_at(kHomeMemberListBreakpoint).mode, HomeLayoutMode.wide);
      expect(_at(kHomeMemberListBreakpoint - 1).mode, HomeLayoutMode.medium);
      expect(_at(kHomeSidebarBreakpoint).mode, HomeLayoutMode.medium);
      expect(_at(kHomeSidebarBreakpoint - 1).mode, HomeLayoutMode.compact);
    });

    test(
      'a dragged-wide channel list is squeezed before a pane is dropped',
      () {
        // 1000pt with a 420pt channel list would leave 268pt of messages; the
        // list is trimmed instead of the roster being thrown into a drawer.
        final layout = _at(1000, channelListWidth: 420);
        expect(layout.mode, HomeLayoutMode.wide);
        expect(layout.channelListWidth, lessThan(420));
        expect(
          layout.channelListWidth,
          greaterThanOrEqualTo(AccordSettings.minChannelListWidth),
        );
        expect(_messagePaneWidth(layout, 1000), kMinMessagePaneWidth);
      },
    );

    test('a preference that already fits is honoured exactly', () {
      expect(_at(1600, channelListWidth: 380).channelListWidth, 380);
    });

    test('the preference is clamped to the settings range', () {
      expect(
        _at(2000, channelListWidth: 10).channelListWidth,
        AccordSettings.minChannelListWidth,
      );
      expect(
        _at(2000, channelListWidth: 5000).channelListWidth,
        AccordSettings.maxChannelListWidth,
      );
    });
  });

  test('the onboarding tour branches on the same width as the panes', () {
    expect(kOnboardingWideBreakpoint, kHomeSidebarBreakpoint);
  });
}
