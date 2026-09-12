import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/withdrawn_attachments.dart';
import 'package:bonfire/features/messaging/views/image_lightbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the lightbox's self-close on withdrawal (#329):
/// [showImageLightbox]'s `attachmentId` wires it to
/// [WithdrawnAttachmentsController] so an AutoMod-withdrawn image doesn't sit
/// open indefinitely. This exercises the actual `StatefulWidget` — the
/// `addPostFrameCallback`/`mounted`/`Navigator.maybePop` wiring — rather than
/// only the pure controller logic already covered elsewhere.
///
/// `pumpAndSettle` can't be used: the dialog holds a `CachedNetworkImage`
/// whose (never-resolving, in this harness) network fetch keeps a frame
/// pending forever. A bounded number of pumps stands in, as elsewhere in this
/// suite.
Future<void> _tick(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext hostContext;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );
  return hostContext;
}

void main() {
  testWidgets(
    'the lightbox closes itself once its attachment is withdrawn',
    (tester) async {
      final context = await _pumpHost(tester);
      final container = ProviderScope.containerOf(context);

      unawaited(
        showImageLightbox(
          context,
          'https://accord.example.test/cdn/a1.png',
          attachmentId: 'a1',
        ),
      );
      await _tick(tester);
      expect(find.byTooltip('Close'), findsOneWidget);

      container
          .read(withdrawnAttachmentsControllerProvider('').notifier)
          .withdraw([AccordAttachment(id: 'a1')]);
      await _tick(tester);

      expect(find.byTooltip('Close'), findsNothing);
    },
  );

  testWidgets(
    'withdrawing a different attachment leaves the lightbox open',
    (tester) async {
      final context = await _pumpHost(tester);
      final container = ProviderScope.containerOf(context);

      unawaited(
        showImageLightbox(
          context,
          'https://accord.example.test/cdn/a1.png',
          attachmentId: 'a1',
        ),
      );
      await _tick(tester);

      container
          .read(withdrawnAttachmentsControllerProvider('').notifier)
          .withdraw([AccordAttachment(id: 'a2')]);
      await _tick(tester);

      expect(find.byTooltip('Close'), findsOneWidget);
    },
  );

  testWidgets(
    'a lightbox opened without an attachment id ignores withdrawals',
    (tester) async {
      final context = await _pumpHost(tester);
      final container = ProviderScope.containerOf(context);

      unawaited(
        showImageLightbox(context, 'https://accord.example.test/cdn/a1.png'),
      );
      await _tick(tester);

      container
          .read(withdrawnAttachmentsControllerProvider('').notifier)
          .withdraw([AccordAttachment(id: 'a1')]);
      await _tick(tester);

      expect(find.byTooltip('Close'), findsOneWidget);
    },
  );
}
