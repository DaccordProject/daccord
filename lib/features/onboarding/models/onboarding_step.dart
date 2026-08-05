import 'package:flutter/material.dart';

/// A named hook a live widget can publish so the first-launch tour (#175) can
/// draw a spotlight over it.
///
/// The tour never reaches into another feature's widget tree by identity — it
/// asks for an [OnboardingAnchorId] and gets back whatever rectangle is on
/// screen for it right now (see `views/onboarding_anchors.dart`). That keeps the
/// coupling to one enum value per surface instead of a web of GlobalKeys owned
/// by five different feature modules.
enum OnboardingAnchorId {
  /// The vertical strip of space/server icons down the left edge (desktop), or
  /// the same rail inside the navigation drawer (mobile).
  spaceRail,

  /// The channel list pane next to the rail.
  channelList,

  /// A voice channel row inside the channel list.
  voiceChannel,

  /// The message composer ("Message #channel") at the bottom of the pane.
  messageComposer,

  /// The scrolling message history.
  messageList,

  /// Mobile only: the hamburger button that opens the rail + channel drawer.
  navMenu,
}

/// One card in the walkthrough.
@immutable
class OnboardingStep {
  const OnboardingStep({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    this.anchors = const <OnboardingAnchorId>[],
  });

  /// Stable identifier, used by tests and analytics-free debug logging.
  final String id;

  final String title;
  final String body;
  final IconData icon;

  /// Candidate anchors in priority order. The first one that resolves to a
  /// visible rectangle wins; when none do (the widget isn't built on this
  /// layout, or is scrolled off screen) the card is simply centred, which is
  /// also the intended presentation for [isIntro]-style steps.
  final List<OnboardingAnchorId> anchors;

  /// A step that never spotlights anything (the welcome / wrap-up cards).
  bool get isCentered => anchors.isEmpty;
}

/// Below this width `AccordHomeScreen` moves the rail and channel list into a
/// drawer and the three-pane layout is gone. Mirrors that screen's private
/// `_wideLayoutBreakpoint` — the tour must not point at a rail that isn't on
/// screen, so it branches on exactly the same number rather than on
/// `shouldUseDesktopLayout` (which is true for short-but-wide windows where the
/// panes are still collapsed).
const double kOnboardingWideBreakpoint = 720;

/// The walkthrough, adapted to the layout actually on screen.
///
/// Both variants cover the same four surfaces the issue asks for — spaces,
/// channels, messaging, voice — but the wide layout can point at each pane
/// directly while the narrow one has to point at the drawer button that reveals
/// them (and merges spaces + channels into one card, since they share it).
List<OnboardingStep> onboardingSteps({required bool wide}) =>
    wide ? _wideSteps : _narrowSteps;

/// Convenience wrapper: picks the variant from a width (see
/// [kOnboardingWideBreakpoint]).
List<OnboardingStep> onboardingStepsForWidth(double width) =>
    onboardingSteps(wide: width >= kOnboardingWideBreakpoint);

const List<OnboardingStep> _wideSteps = <OnboardingStep>[
  OnboardingStep(
    id: 'welcome',
    title: 'Welcome to Daccord',
    body:
        'A quick tour of the four things you need: your spaces, your channels, '
        'sending messages, and voice. It takes about thirty seconds — you can '
        'skip it at any point and replay it later from Settings.',
    icon: Icons.waving_hand_outlined,
  ),
  OnboardingStep(
    id: 'spaces',
    title: 'Spaces live here',
    body:
        'Every community you join — on any server you connect to — gets an icon '
        'in this rail. Click one to switch to it, drag to reorder, and use the '
        '+ button to connect to another server or join a space.',
    icon: Icons.workspaces_outline,
    anchors: <OnboardingAnchorId>[OnboardingAnchorId.spaceRail],
  ),
  OnboardingStep(
    id: 'channels',
    title: 'Channels inside a space',
    body:
        'The selected space lists its channels here, grouped into categories '
        'you can collapse. Text channels open a conversation; a bold name means '
        'there is something new to read.',
    icon: Icons.tag,
    anchors: <OnboardingAnchorId>[OnboardingAnchorId.channelList],
  ),
  OnboardingStep(
    id: 'messaging',
    title: 'Say something',
    body:
        'Type here to post to the open channel. Markdown, @mentions, emoji and '
        'file drag-and-drop all work, and hovering a message reveals reply, '
        'react, edit and thread actions.',
    icon: Icons.chat_bubble_outline,
    anchors: <OnboardingAnchorId>[
      OnboardingAnchorId.messageComposer,
      OnboardingAnchorId.messageList,
    ],
  ),
  OnboardingStep(
    id: 'voice',
    title: 'Voice, video and screen share',
    body:
        'Channels with a speaker icon are voice channels. Opening one shows its '
        'lobby — who is in the call and a Join button — so a stray click never '
        'drops you into a live call. Once connected you can turn on your camera '
        'or share a screen.',
    icon: Icons.headset_mic_outlined,
    anchors: <OnboardingAnchorId>[
      OnboardingAnchorId.voiceChannel,
      OnboardingAnchorId.channelList,
    ],
  ),
  OnboardingStep(
    id: 'help',
    title: "That's the tour",
    body:
        'Everything else — appearance, notifications, voice devices, accounts — '
        'lives in Settings, at the bottom of the space rail. Stuck, or found a '
        'bug? Help & support has the docs and the issue tracker.',
    icon: Icons.check_circle_outline,
  ),
];

const List<OnboardingStep> _narrowSteps = <OnboardingStep>[
  OnboardingStep(
    id: 'welcome',
    title: 'Welcome to Daccord',
    body:
        'A quick tour of the four things you need: your spaces, your channels, '
        'sending messages, and voice. It takes about thirty seconds — you can '
        'skip it at any point and replay it later from Settings.',
    icon: Icons.waving_hand_outlined,
  ),
  // On a phone the rail and the channel list are both inside the navigation
  // drawer, so they get one card pointing at the button that reveals them
  // rather than two cards pointing at widgets that aren't on screen.
  OnboardingStep(
    id: 'spaces',
    title: 'Spaces and channels',
    body:
        'Tap here (or swipe in from the left edge) for the sidebar. It holds the '
        'rail of every space you have joined, and the channel list for whichever '
        'one is selected.',
    icon: Icons.workspaces_outline,
    anchors: <OnboardingAnchorId>[
      OnboardingAnchorId.navMenu,
      OnboardingAnchorId.spaceRail,
    ],
  ),
  OnboardingStep(
    id: 'channels',
    title: 'Switching channels',
    body:
        'Pick a channel in that sidebar and it opens here as a tab. The tab '
        'strip across the top keeps your recent channels one tap away, and a '
        'bold name means unread messages.',
    icon: Icons.tag,
    anchors: <OnboardingAnchorId>[
      OnboardingAnchorId.channelList,
      OnboardingAnchorId.navMenu,
    ],
  ),
  OnboardingStep(
    id: 'messaging',
    title: 'Say something',
    body:
        'Type here to post to the open channel. Markdown, @mentions, emoji and '
        'attachments all work, and long-pressing a message reveals reply, react '
        'and thread actions.',
    icon: Icons.chat_bubble_outline,
    anchors: <OnboardingAnchorId>[
      OnboardingAnchorId.messageComposer,
      OnboardingAnchorId.messageList,
    ],
  ),
  OnboardingStep(
    id: 'voice',
    title: 'Voice, video and screen share',
    body:
        'Channels with a speaker icon in the sidebar are voice channels. Opening '
        'one shows its lobby — who is in the call and a Join button — so a stray '
        'tap never drops you into a live call.',
    icon: Icons.headset_mic_outlined,
    anchors: <OnboardingAnchorId>[
      OnboardingAnchorId.voiceChannel,
      OnboardingAnchorId.navMenu,
    ],
  ),
  OnboardingStep(
    id: 'help',
    title: "That's the tour",
    body:
        'Everything else — appearance, notifications, voice devices, accounts — '
        'lives in Settings, reachable from the bottom of the space rail in the '
        'sidebar. Stuck, or found a bug? Help & support has the docs and the '
        'issue tracker.',
    icon: Icons.check_circle_outline,
  ),
];
