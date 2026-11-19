import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/comments/saved_replies_store.dart';
import 'package:pili_aurora_next/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:pili_aurora_next/utils/utils.dart';

final savedRepliesProvider = NotifierProvider.autoDispose(
  SavedReplies.new,
);

class SavedReplies extends Notifier<List<ReplyInfo>> {
  final _store = const SavedRepliesStore();

  @override
  List<ReplyInfo> build() => _read();

  List<ReplyInfo> _read() => List.unmodifiable(
    _store.read()..sort((first, second) => second.ctime.compareTo(first.ctime)),
  );

  void remove(ReplyInfo reply, int? childIndex) {
    final index = state.indexWhere((item) => item.id == reply.id);
    if (index < 0) return;
    if (childIndex != null) {
      if (childIndex < 0 || childIndex >= reply.replies.length) return;
      final childId = reply.replies[childIndex].id;
      state[index].replies.removeWhere((child) => child.id == childId);
      state = List.unmodifiable(state);
      return;
    }
    state = List.unmodifiable([...state]..removeAt(index));
  }

  String exportReplies() => Utils.jsonEncoder.convert([
    for (final reply in state) reply.toProto3Json(),
  ]);

  Future<void> importReplies(List<dynamic> entries) async {
    await _store.importReplies(entries);
    if (ref.mounted) state = _read();
  }

  Future<void> clear() async {
    await _store.clear();
    if (ref.mounted) state = _read();
  }
}
