import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/attachment_withdrawal.dart';
import 'package:flutter_test/flutter_test.dart';

AccordAttachment _att(String id, {String url = ''}) =>
    AccordAttachment(id: id, filename: '$id.png', url: url);

AccordMessage _msg(List<AccordAttachment> attachments) =>
    AccordMessage(id: 'm1', channelId: 'c1', attachments: attachments);

void main() {
  group('withdrawnAttachments', () {
    test('lists what the previous copy had that the update no longer does', () {
      final previous = _msg([_att('a1'), _att('a2'), _att('a3')]);
      final next = _msg([_att('a2')]);

      expect(withdrawnAttachments(previous, next).map((a) => a.id), [
        'a1',
        'a3',
      ]);
    });

    test('an edit that adds or reorders attachments withdraws none', () {
      final previous = _msg([_att('a1'), _att('a2')]);
      final next = _msg([_att('a2'), _att('a1'), _att('a3')]);

      expect(withdrawnAttachments(previous, next), isEmpty);
    });

    test('nothing cached means nothing to withdraw', () {
      expect(withdrawnAttachments(null, _msg([])), isEmpty);
      expect(withdrawnAttachments(_msg([]), _msg([])), isEmpty);
    });

    test('falls back to the url when the server omits ids', () {
      final previous = _msg([_att('', url: '/cdn/x.png')]);
      expect(
        withdrawnAttachments(previous, _msg([_att('', url: '/cdn/x.png')])),
        isEmpty,
      );
      expect(withdrawnAttachments(previous, _msg([])).single.url, '/cdn/x.png');
    });
  });

  group('removeAttachmentInPlace', () {
    test('strips the matching attachment and returns it', () {
      final message = _msg([_att('a1'), _att('a2')]);

      final removed = removeAttachmentInPlace(message, 'a2');

      expect(removed?.id, 'a2');
      expect(message.attachments.map((a) => a.id), ['a1']);
    });

    test('returns null and leaves the message alone for an unknown id', () {
      final message = _msg([_att('a1')]);

      expect(removeAttachmentInPlace(message, 'nope'), isNull);
      expect(message.attachments.map((a) => a.id), ['a1']);
    });
  });
}
