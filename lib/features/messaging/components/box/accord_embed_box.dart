import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/components/box/accord_markdown_box.dart';
import 'package:bonfire/features/messaging/components/inline_video_player.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a single Accord message [AccordEmbed] — a rich card with an accent
/// left border, optional author/title/description/fields/image/thumbnail/footer.
/// Mirrors the Godot reference client's `embed.tscn` layout. Embed fields are
/// loosely typed on the model, so each accessor is defensive.
class AccordEmbedBox extends StatelessWidget {
  const AccordEmbedBox({super.key, required this.embed, this.cdnUrl});

  final AccordEmbed embed;
  final String? cdnUrl;

  static const _maxImageWidth = 400.0;
  static const _maxImageHeight = 300.0;
  static const _thumbnailSize = 80.0;

  String? _resolve(String? url) {
    if (url == null || url.isEmpty) return null;
    return AccordCDN.resolvePath(url, cdnUrl: cdnUrl ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);

    final author = _asMap(embed.author);
    final authorName = _str(author?['name']);
    final authorUrl = _str(author?['url']);
    final authorIcon = _resolve(_str(author?['icon_url']));

    final title = _str(embed.title);
    final embedUrl = _str(embed.url);
    final description = _str(embed.description);
    final fields = embed.fields ?? const [];
    final imageUrl = _resolve(_imageUrl(embed.image));
    final thumbUrl = _resolve(_imageUrl(embed.thumbnail));
    final footer = _footerText(embed.footer);
    final timestamp = _formatTimestamp(embed.timestamp);
    final isVideo = _str(embed.type)?.toLowerCase() == 'video';
    final borderColor = _color(embed.color) ?? colors.primary;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (authorName != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (authorIcon != null) ...[
                ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: authorIcon,
                    width: 20,
                    height: 20,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: _LinkText(
                  text: authorName,
                  url: authorUrl,
                  style: theme.textTheme.labelLarge!
                      .copyWith(color: colors.dirtyWhite),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        if (title != null) ...[
          _LinkText(
            text: title,
            url: embedUrl,
            style: theme.textTheme.titleSmall!.copyWith(
              color: embedUrl != null ? colors.primary : colors.dirtyWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (description != null) AccordMarkdownBox(content: description),
        if (fields.isNotEmpty) ...[
          const SizedBox(height: 6),
          _EmbedFields(fields: fields),
        ],
        if (imageUrl != null) ...[
          const SizedBox(height: 8),
          // For video-type embeds we play the linked URL inline via media_kit
          // when present; otherwise we fall back to a tap-to-launch poster
          // (no inline playback, but a clear play affordance vs. the previous
          // static image). For non-video embeds the image renders as before.
          if (isVideo && embedUrl != null)
            InlineVideoPlayer(
              url: embedUrl,
              filename: title ?? 'video',
              width: _maxImageWidth,
              height: _maxImageHeight,
            )
          else if (isVideo)
            _VideoPoster(
              imageUrl: imageUrl,
              onTap: embedUrl == null
                  ? null
                  : () => launchUrl(Uri.parse(embedUrl),
                      mode: LaunchMode.externalApplication),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _maxImageWidth,
                  maxHeight: _maxImageHeight,
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
        if (footer != null || timestamp != null) ...[
          const SizedBox(height: 6),
          Text(
            _joinFooter(footer, timestamp),
            style: theme.textTheme.labelSmall!.copyWith(color: colors.gray),
          ),
        ],
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxWidth: 460),
      decoration: BoxDecoration(
        color: colors.foreground,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      padding: const EdgeInsets.all(12),
      child: thumbUrl == null
          ? body
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: body),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: thumbUrl,
                    width: _thumbnailSize,
                    height: _thumbnailSize,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Renders embed fields, grouping consecutive inline fields into rows of up to
/// three, matching the reference client.
class _EmbedFields extends StatelessWidget {
  const _EmbedFields({required this.fields});

  final List<dynamic> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final rows = <Widget>[];

    Widget cell(Map<String, dynamic> field) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_str(field['name']) ?? '',
              style: theme.textTheme.labelMedium!
                  .copyWith(color: colors.dirtyWhite, fontWeight: FontWeight.bold)),
          AccordMarkdownBox(content: _str(field['value']) ?? ''),
        ],
      );
    }

    var i = 0;
    while (i < fields.length) {
      final field = _asMap(fields[i]);
      if (field == null) {
        i++;
        continue;
      }
      final inline = field['inline'] == true;
      if (inline) {
        final cells = <Widget>[];
        while (i < fields.length && cells.length < 3) {
          final f = _asMap(fields[i]);
          if (f == null || f['inline'] != true) break;
          cells.add(Expanded(child: cell(f)));
          i++;
        }
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < cells.length; c++) ...[
                if (c > 0) const SizedBox(width: 12),
                cells[c],
              ],
            ],
          ),
        ));
      } else {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: cell(field),
        ));
        i++;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

/// Text that opens [url] externally when tapped, or plain text when [url] is
/// null.
class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, required this.style, this.url});

  final String text;
  final String? url;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (url == null) return Text(text, style: style);
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: Text(text, style: style),
    );
  }
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _str(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// Embed image/thumbnail fields are either a bare URL string or a `{url: ...}`
/// object depending on the server.
String? _imageUrl(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  return _str(_asMap(value)?['url']);
}

/// Footer is either a string or a `{text, icon_url}` object.
String? _footerText(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  return _str(_asMap(value)?['text']);
}

/// Embed color is an RGB integer (no alpha); returns null when absent.
Color? _color(Object? value) {
  if (value is int) return Color(0xFF000000 | (value & 0xFFFFFF));
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return Color(0xFF000000 | (parsed & 0xFFFFFF));
  }
  return null;
}

/// Joins an embed footer text with its timestamp using a bullet separator,
/// matching the reference client. Either may be null.
String _joinFooter(String? footer, String? timestamp) {
  if (footer != null && timestamp != null) return "$footer \u2022 $timestamp";
  return footer ?? timestamp ?? "";
}

/// Parses an embed `timestamp` ISO-8601 string into a human-readable
/// "YYYY-MM-DD HH:MM" in the local time zone. Returns null when missing or
/// unparseable so the footer collapses gracefully.
String? _formatTimestamp(Object? value) {
  final s = _str(value);
  if (s == null) return null;
  final dt = DateTime.tryParse(s);
  if (dt == null) return null;
  final local = dt.toLocal();
  String pad(int n) => n.toString().padLeft(2, "0");
  return "${local.year}-${pad(local.month)}-${pad(local.day)} "
      "${pad(local.hour)}:${pad(local.minute)}";
}

/// A video-embed poster: the thumbnail with a large play-button overlay. Used
/// when an inline media_kit player is not appropriate (e.g. the embed only
/// carries an image + an external video URL).
class _VideoPoster extends StatelessWidget {
  const _VideoPoster({required this.imageUrl, this.onTap});

  final String imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400,
              maxHeight: 300,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
