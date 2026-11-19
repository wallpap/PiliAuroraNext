import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/utils/storage.dart';

class SavedRepliesStore {
  const SavedRepliesStore();

  List<ReplyInfo> read() =>
      GStorage.reply?.values.map(ReplyInfo.fromBuffer).toList() ?? [];

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
