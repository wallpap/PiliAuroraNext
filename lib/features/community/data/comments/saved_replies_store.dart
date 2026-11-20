import 'package:pili_aurora_next/features/community/data/comments/comment_protocol.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/services/settings/storage.dart';
import 'package:pili_aurora_next/core/serialization/pretty_json.dart';

class SavedRepliesStore {
  const SavedRepliesStore();

  bool get available => GStorage.reply != null;

  List<CommentReply> read() =>
      GStorage.reply?.values
          .map((bytes) => commentFromProtocol(ReplyInfo.fromBuffer(bytes)))
          .toList() ??
      [];

  String exportReplies(List<CommentReply> replies) =>
      prettyJsonEncoder.convert([
        for (final reply in replies) commentForArchive(reply).toProto3Json(),
      ]);

  Future<void> writeDebugCopy(CommentReply reply, {bool batch = false}) async {
    final box = GStorage.reply;
    if (box == null) return;
    final data =
        (commentForArchive(reply, includeReplies: false)
              ..unknownFields.clear()
              ..clearTrackInfo())
            .writeToBuffer();
    if (batch) {
      final start = reply.oid.toInt();
      await box.putAll({
        for (var id = start; id < start + 1000; id++) id.toString(): data,
      });
    } else {
      await box.put(reply.id.toString(), data);
    }
  }

  Future<void> deleteDebugCopy(CommentReply reply) async {
    await GStorage.reply?.delete(reply.id.toString());
  }

  Future<void> importReplies(List<dynamic> entries) async {
    await GStorage.reply?.putAll({
      for (final entry in entries)
        entry['id'].toString(): (ReplyInfo.create()..mergeFromProto3Json(entry))
            .writeToBuffer(),
    });
  }

  Future<void> clear() async {
    await GStorage.reply?.clear();
  }
}
