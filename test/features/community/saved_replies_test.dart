import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/community/application/comments/saved_replies.dart';
import 'package:pili_aurora_next/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

void main() {
  test('评论归档重新排序后按原评论 ID 消费删除回执', () async {
    final initial = ReplyInfo(id: Int64(1), ctime: Int64(100));
    final newer = ReplyInfo(id: Int64(2), ctime: Int64(200));
    final storage = MemoryBox<Uint8List>({'1': initial.writeToBuffer()});
    GStorage.reply = storage;
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
}
