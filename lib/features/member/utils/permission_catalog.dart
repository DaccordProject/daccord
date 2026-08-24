import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/string_ext.dart';

/// Shared permission grouping for role grants and channel overwrites.
const accordPermissionGroups = <({String label, List<String> permissions})>[
  (
    label: 'General',
    permissions: [
      AccordPermission.viewChannel,
      AccordPermission.createInvites,
      AccordPermission.changeNickname,
      AccordPermission.manageNicknames,
      AccordPermission.useCommands,
    ],
  ),
  (
    label: 'Text',
    permissions: [
      AccordPermission.sendMessages,
      AccordPermission.sendTts,
      AccordPermission.embedLinks,
      AccordPermission.attachFiles,
      AccordPermission.readHistory,
      AccordPermission.mentionEveryone,
      AccordPermission.useExternalEmojis,
      AccordPermission.useExternalStickers,
      AccordPermission.addReactions,
    ],
  ),
  (
    label: 'Threads',
    permissions: [
      AccordPermission.manageThreads,
      AccordPermission.createThreads,
      AccordPermission.sendInThreads,
    ],
  ),
  (
    label: 'Voice',
    permissions: [
      AccordPermission.connect,
      AccordPermission.speak,
      AccordPermission.stream,
      AccordPermission.useVad,
      AccordPermission.prioritySpeaker,
      AccordPermission.muteMembers,
      AccordPermission.deafenMembers,
      AccordPermission.moveMembers,
      AccordPermission.useSoundboard,
      AccordPermission.manageSoundboard,
    ],
  ),
  (
    label: 'Moderation',
    permissions: [
      AccordPermission.kickMembers,
      AccordPermission.banMembers,
      AccordPermission.moderateMembers,
      AccordPermission.manageMessages,
      AccordPermission.manageAutomod,
      AccordPermission.viewAuditLog,
    ],
  ),
  (
    label: 'Administration',
    permissions: [
      AccordPermission.administrator,
      AccordPermission.manageChannels,
      AccordPermission.manageSpace,
      AccordPermission.manageRoles,
      AccordPermission.manageWebhooks,
      AccordPermission.manageEmojis,
      AccordPermission.manageEvents,
    ],
  ),
];

/// Human-facing permission names shared by both editors.
String accordPermissionLabel(String permission) => switch (permission) {
  AccordPermission.mentionEveryone => 'Mention @everyone, @here, and all roles',
  _ => titleCaseFromToken(permission),
};
