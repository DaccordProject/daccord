import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccordMessage _message(
  String id,
  String channelId,
  String content, {
  List<AccordAttachment> attachments = const [],
}) => AccordMessage(
  id: id,
  channelId: channelId,
  authorId: 'user',
  content: content,
  timestamp: '2026-08-24T12:00:00Z',
  attachments: attachments,
);

void main() {
  test('live DM activity updates preview and moves conversation to front', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      dmChannelsControllerProvider('server').notifier,
    );
    controller.setChannels([
      AccordChannel(id: 'a', type: 'dm'),
      AccordChannel(id: 'b', type: 'dm'),
    ]);

    controller.applyMessage(_message('m1', 'b', '  hello\nthere  '));

    expect(
      container
          .read(dmChannelsControllerProvider('server'))
          ?.map((channel) => channel.id),
      ['b', 'a'],
    );
    expect(controller.previewFor('b'), 'hello there');
  });

  test('edit/delete only changes the current last-message preview', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      dmChannelsControllerProvider('server').notifier,
    );
    controller.setChannels([AccordChannel(id: 'dm', type: 'dm')]);
    controller.applyMessage(_message('latest', 'dm', 'before'));

    controller.updateMessagePreview(_message('older', 'dm', 'ignore'));
    expect(controller.previewFor('dm'), 'before');

    controller.updateMessagePreview(_message('latest', 'dm', 'after'));
    expect(controller.previewFor('dm'), 'after');

    controller.removeMessagePreview('dm', 'latest');
    expect(controller.previewFor('dm'), isNull);
  });
}
