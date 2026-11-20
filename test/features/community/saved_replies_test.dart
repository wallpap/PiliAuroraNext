import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/comments/saved_replies.dart';
import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show Content, Emote, Picture, ReplyInfo;
import 'package:pili_aurora_next/services/settings/storage.dart';

import '../../support/memory_box.dart';

void main() {
  final storage = MemoryBox<Uint8List>();
  setUpAll(() => GStorage.reply = storage);
  setUp(storage.clear);

  test('评论归档重新排序后按原评论 ID 消费删除回执', () async {
    final initial = ReplyInfo(id: Int64(1), ctime: Int64(100));
    final newer = ReplyInfo(id: Int64(2), ctime: Int64(200));
    await storage.put('1', initial.writeToBuffer());
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(savedRepliesProvider, (_, _) {});
    final archive = container.read(savedRepliesProvider.notifier);
    final deleting = subscription.read().single;

    await archive.importReplies([newer.toProto3Json()]);
    expect(subscription.read().map((item) => item.id.toInt()), [2, 1]);

    await storage.delete('1');
    archive.remove(deleting, null);
    expect(jsonDecode(archive.exportReplies()), [newer.toProto3Json()]);
  });

  test('旧评论归档保留字段存在性和未投影数据，并导出已确认的交互', () async {
    final original = ReplyInfo(
      id: Int64(9223372036854775806),
      root: Int64.ZERO,
      ctime: Int64(100),
      content: Content(
        message: '正文',
        pictures: [Picture(imgSrc: 'image', imgWidth: 240, imgSize: 123)],
        emotes: [
          MapEntry('[动画]', Emote(url: 'png', gifUrl: 'gif', webpUrl: '')),
        ],
      ),
      replies: [
        ReplyInfo(id: Int64(2)),
        ReplyInfo(id: Int64(3)),
      ],
    );
    await storage.put(original.id.toString(), original.writeToBuffer());
    final container = ProviderContainer.test();
    final subscription = container.listen(savedRepliesProvider, (_, _) {});
    final archive = container.read(savedRepliesProvider.notifier);
    final item = subscription.read().single;

    expect(item.rootId, Int64.ZERO);
    expect(item.content.emotes['[动画]']?.webpUrl, '');
    expect(commentPicturesForAntifraud(item), [
      original.content.pictures.single.toProto3Json(),
    ]);
    expect(jsonDecode(archive.exportReplies()), [original.toProto3Json()]);
    archive.remove(item, 0);
    item.like = Int64.ONE;
    item.replyControl.action = Int64.ONE;
    item.replyControl.showTranslation = true;
    item.translatedContent = commentContentFromProtocol(Content(message: '译文'));

    final exported = (jsonDecode(archive.exportReplies()) as List).single;
    final parsed = ReplyInfo()..mergeFromProto3Json(exported);
    expect(parsed.id, original.id);
    expect(parsed.hasRoot(), isTrue);
    expect(parsed.root, Int64.ZERO);
    expect(parsed.content, original.content);
    expect(parsed.replies.map((reply) => reply.id.toInt()), [3]);
    expect(parsed.like, Int64.ONE);
    expect(parsed.replyControl.action, Int64.ONE);
    expect(parsed.replyControl.showTranslation, isTrue);
    expect(parsed.translatedContent.message, '译文');
    expect(storage.values.single, original.writeToBuffer());
  });
}
