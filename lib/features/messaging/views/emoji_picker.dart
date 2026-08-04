import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/horizontal_wheel_scroll.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The user's selection from the emoji picker. [id] is null for built-in
/// unicode emoji (where [char] is the character to insert/react with); for a
/// custom space emoji [id] is set, [char] is empty, and [imageUrl] points at
/// the rendered glyph.
class EmojiPick {
  const EmojiPick({required this.name, this.char = '', this.id, this.imageUrl});

  final String name;
  final String char;
  final String? id;
  final String? imageUrl;

  bool get isCustom => id != null;

  /// The reaction token the REST API expects: the bare unicode char for
  /// built-ins, or `name:id` for custom emoji.
  String get reactionToken => isCustom ? '$name:$id' : char;

  /// The text inserted into the composer: the char for built-ins, or a
  /// `:name:` shortcode for custom emoji.
  String get composerText => isCustom ? ':$name:' : char;

  /// The token stored in the recents list, from which [_pickFromRecent] can
  /// reconstruct this pick.
  String get recentToken => isCustom ? '$name:$id' : char;
}

/// Shows the full emoji picker as a modal bottom sheet and resolves to the
/// chosen [EmojiPick], or null if dismissed. Pass [spaceId] to surface that
/// space's custom emoji (and to record recents); standard unicode emoji are
/// always available.
Future<EmojiPick?> showAccordEmojiPicker(
  BuildContext context, {
  String? spaceId,
}) {
  return showModalBottomSheet<EmojiPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EmojiPickerSheet(spaceId: spaceId),
  );
}

class _EmojiPickerSheet extends ConsumerStatefulWidget {
  const _EmojiPickerSheet({this.spaceId});

  final String? spaceId;

  @override
  ConsumerState<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

/// A pseudo-category selected by the tab row in addition to the standard
/// [EmojiCategory] values.
enum _Tab { recent, custom }

class _EmojiPickerSheetState extends ConsumerState<_EmojiPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Either a [_Tab] (recent/custom) or an [EmojiCategory].
  Object _selected = EmojiCategory.smileys;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? get _cdnUrl => ref.readCdnUrl();

  List<AccordEmoji> get _customEmoji {
    final spaceId = widget.spaceId;
    if (spaceId == null) return const [];
    return ref.watch(accordEmojisControllerProvider(spaceId)) ?? const [];
  }

  void _pick(EmojiPick pick) {
    final spaceId = widget.spaceId;
    if (spaceId != null) {
      ref
          .read(settingsControllerProvider.notifier)
          .addRecentEmoji(pick.recentToken);
    }
    Navigator.of(context).pop(pick);
  }

  /// Reconstructs an [EmojiPick] from a stored recent token, resolving custom
  /// tokens (`name:id`) against the current space's emoji.
  EmojiPick? _pickFromRecent(String token, List<AccordEmoji> custom) {
    final sep = token.lastIndexOf(':');
    if (sep > 0 && sep < token.length - 1) {
      final id = token.substring(sep + 1);
      final match = custom.firstWhere(
        (e) => e.id == id,
        orElse: () => AccordEmoji(),
      );
      if (match.id == null) return null; // custom emoji no longer available
      return EmojiPick(
        name: match.name,
        id: match.id,
        imageUrl: _emojiImageUrl(match),
      );
    }
    // Unicode char: recover its short name from the catalog when known.
    final entry = kEmojiCatalog.firstWhere(
      (e) => e.char == token,
      orElse: () => EmojiEntry(token, token, EmojiCategory.smileys),
    );
    return EmojiPick(name: entry.name, char: token);
  }

  String? _emojiImageUrl(AccordEmoji emoji) => accordEmojiUrl(emoji, _cdnUrl);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final custom = _customEmoji;
    final recents = ref.watch(
      settingsControllerProvider.select((s) => s.recentEmoji),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                style: Theme.of(context).textTheme.bodyLarge,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: colors.darkGray,
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.gray),
                  hintText: 'Search emoji',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_query.isEmpty)
              _TabBar(
                hasCustom: custom.isNotEmpty,
                hasRecent: recents.isNotEmpty,
                selected: _selected,
                onSelect: (s) => setState(() => _selected = s),
              ),
            Expanded(
              child: _query.isNotEmpty
                  ? _buildSearchGrid(colors, custom)
                  : _buildCategoryGrid(colors, custom, recents),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchGrid(
    BonfireThemeExtension colors,
    List<AccordEmoji> custom,
  ) {
    final unicodeHits = [
      for (final e in kEmojiCatalog)
        if (e.matches(_query)) e,
    ];
    final customHits = [
      for (final e in custom)
        if (e.name.toLowerCase().contains(_query)) e,
    ];
    if (unicodeHits.isEmpty && customHits.isEmpty) {
      return _empty(colors, 'No emoji match "$_query"');
    }
    return _grid([
      for (final e in customHits) _customCell(e),
      for (final e in unicodeHits) _unicodeCell(e),
    ]);
  }

  Widget _buildCategoryGrid(
    BonfireThemeExtension colors,
    List<AccordEmoji> custom,
    List<String> recents,
  ) {
    final selected = _selected;
    if (selected == _Tab.recent) {
      final picks = [
        for (final token in recents)
          if (_pickFromRecent(token, custom) case final p?) p,
      ];
      if (picks.isEmpty) return _empty(colors, 'No recent emoji yet');
      return _grid([for (final p in picks) _pickCell(p)]);
    }
    if (selected == _Tab.custom) {
      if (custom.isEmpty) {
        return _empty(colors, 'This space has no custom emoji');
      }
      return _grid([for (final e in custom) _customCell(e)]);
    }
    final category = selected as EmojiCategory;
    return _grid([
      for (final e in kEmojiCatalog)
        if (e.category == category) _unicodeCell(e),
    ]);
  }

  Widget _grid(List<Widget> cells) {
    // Fixed ~36px tiles so cell height tracks the glyph size (not the column
    // width) — keeps the grid dense regardless of panel width, instead of the
    // sparse square cells `GridView.count(crossAxisCount: 8)` produced.
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 40,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: cells.length,
      itemBuilder: (context, i) => cells[i],
    );
  }

  Widget _empty(BonfireThemeExtension colors, String message) {
    return Center(
      child: Text(message, style: TextStyle(color: colors.gray)),
    );
  }

  Widget _unicodeCell(EmojiEntry entry) {
    return _cell(
      tooltip: entry.name,
      onTap: () => _pick(EmojiPick(name: entry.name, char: entry.char)),
      child: Text(entry.char, style: const TextStyle(fontSize: 26)),
    );
  }

  Widget _customCell(AccordEmoji emoji) {
    final url = _emojiImageUrl(emoji);
    return _cell(
      tooltip: emoji.name,
      onTap: () =>
          _pick(EmojiPick(name: emoji.name, id: emoji.id, imageUrl: url)),
      child: url == null
          ? Text(':${emoji.name}:', style: const TextStyle(fontSize: 9))
          : CachedNetworkImage(
              imageUrl: url,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
    );
  }

  Widget _pickCell(EmojiPick pick) {
    return _cell(
      tooltip: pick.name,
      onTap: () => _pick(pick),
      child: pick.isCustom
          ? (pick.imageUrl == null
                ? Text(':${pick.name}:', style: const TextStyle(fontSize: 9))
                : CachedNetworkImage(
                    imageUrl: pick.imageUrl!,
                    width: 26,
                    height: 26,
                    fit: BoxFit.contain,
                  ))
          : Text(pick.char, style: const TextStyle(fontSize: 26)),
    );
  }

  Widget _cell({
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}

/// The horizontal category selector: Recent and Custom (when populated) plus
/// the nine standard unicode categories.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.hasCustom,
    required this.hasRecent,
    required this.selected,
    required this.onSelect,
  });

  final bool hasCustom;
  final bool hasRecent;
  final Object selected;
  final ValueChanged<Object> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 40,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: HorizontalWheelScroll(
          builder: (context, controller) => ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (hasRecent) _tab(colors, _Tab.recent, Icons.history, 'Recent'),
              if (hasCustom)
                _tab(
                  colors,
                  _Tab.custom,
                  Icons.workspace_premium_outlined,
                  'Custom',
                ),
              for (final c in EmojiCategory.values)
                _tab(colors, c, c.icon, c.label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(
    BonfireThemeExtension colors,
    Object value,
    IconData icon,
    String label,
  ) {
    final active = selected == value;
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: () => onSelect(value),
        icon: Icon(
          icon,
          size: 20,
          color: active ? colors.primary : colors.gray,
        ),
      ),
    );
  }
}
