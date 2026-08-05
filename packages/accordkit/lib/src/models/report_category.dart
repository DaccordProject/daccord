/// Report categories accepted by the Accord server.
///
/// Mirrors `REPORT_CATEGORIES` in accordserver's `src/routes/reports.rs`,
/// including its order: everyday moderation reasons first, severe/legal ones
/// after, `other` last. The server also serves this list from
/// `GET /reports/categories` ([ReportsApi.categories]) — prefer that at
/// runtime and use these values as the offline fallback.
enum AccordReportCategory {
  spam('spam', 'Spam'),
  harassment('harassment', 'Harassment or bullying'),
  hate('hate', 'Hate speech'),
  nsfw('nsfw', 'Inappropriate content'),
  violence('violence', 'Violence or threats'),
  selfHarm('self_harm', 'Self-harm or suicide'),
  csam('csam', 'Child sexual abuse material'),
  terrorism('terrorism', 'Terrorism or violent extremism'),
  fraud('fraud', 'Fraud or scam'),
  other('other', 'Other');

  const AccordReportCategory(this.value, this.label);

  /// Wire value sent as `category`.
  final String value;

  /// Human-readable label for report and moderation UIs.
  final String label;

  /// Non-canonical spellings the server still accepts, mapped to the canonical
  /// value so stored reports from older clients render with a label.
  static const _aliases = <String, String>{'hate_speech': 'hate'};

  /// Returns the category matching [value] (or a known alias), or `null` if
  /// unknown.
  static AccordReportCategory? fromValue(String? value) {
    if (value == null) return null;
    final canonical = _aliases[value] ?? value;
    for (final c in AccordReportCategory.values) {
      if (c.value == canonical) return c;
    }
    return null;
  }

  /// Human-readable label for a raw wire [value], falling back to the raw
  /// string so unknown/new server categories still render.
  static String labelFor(String? value) =>
      fromValue(value)?.label ?? (value ?? '');
}
