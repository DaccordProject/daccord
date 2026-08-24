import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/moderation_report_row.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = BonfireThemeExtension(
  foreground: Color(0xff202020),
  background: Color(0xff101010),
  dirtyWhite: Color(0xffeeeeee),
  gray: Color(0xff888888),
  darkGray: Color(0xff444444),
  primary: Color(0xff3366ff),
  red: Color(0xffff3333),
  green: Color(0xff33ff66),
  yellow: Color(0xffffcc33),
);

Widget _host(AccordReport report, ValueChanged<AccordReport> onDelete) {
  return MaterialApp(
    theme: ThemeData(extensions: const [_theme]),
    home: Scaffold(
      body: ModerationReportRow(
        report: report,
        busy: false,
        onDismiss: (_) {},
        onResolve: (_) {},
        onDeleteMessage: onDelete,
        onKick: (_) {},
        onBan: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows actions derived from the typed report', (tester) async {
    final report = AccordReport.fromJson({
      'id': '1',
      'target_type': 'message',
      'target_id': '2',
      'channel_id': '3',
      'author_id': '4',
      'category': 'harassment',
      'description': 'Repeated insults',
    });
    AccordReport? deleted;

    await tester.pumpWidget(_host(report, (value) => deleted = value));

    expect(find.text('Harassment or bullying'), findsOneWidget);
    expect(find.text('Repeated insults'), findsOneWidget);
    expect(find.text('Delete msg'), findsOneWidget);
    expect(find.text('Kick'), findsOneWidget);
    expect(find.text('Ban'), findsOneWidget);

    await tester.tap(find.text('Delete msg'));
    expect(deleted, same(report));
  });

  testWidgets('hides target-specific actions when attribution is absent', (
    tester,
  ) async {
    final report = AccordReport(
      id: '1',
      targetType: 'other',
      targetId: '2',
      category: 'new_server_category',
    );

    await tester.pumpWidget(_host(report, (_) {}));

    expect(find.text('new_server_category'), findsOneWidget);
    expect(find.text('Delete msg'), findsNothing);
    expect(find.text('Kick'), findsNothing);
    expect(find.text('Ban'), findsNothing);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
  });
}
