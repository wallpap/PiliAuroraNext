import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/comments/saved_replies_store.dart';
import 'package:pili_aurora_next/features/community/domain/comment.dart';

const _store = SavedRepliesStore();

bool get commentArchiveAvailable => _store.available;
Future<void> saveDebugComment(CommentReply reply, {bool batch = false}) =>
    _store.writeDebugCopy(reply, batch: batch);
Future<void> deleteDebugComment(CommentReply reply) =>
    _store.deleteDebugCopy(reply);

final savedRepliesProvider = NotifierProvider.autoDispose(
  SavedReplies.new,
);

class SavedReplies extends Notifier<List<CommentReply>> {
  @override
  List<CommentReply> build() => _read();

  List<CommentReply> _read() => List.unmodifiable(
    _store.read()..sort((first, second) => second.ctime.compareTo(first.ctime)),
  );

  void remove(CommentReply reply, int? childIndex) {
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

  String exportReplies() => _store.exportReplies(state);

  Future<void> importReplies(List<dynamic> entries) async {
    await _store.importReplies(entries);
    if (ref.mounted) state = _read();
  }

  Future<void> clear() async {
    await _store.clear();
    if (ref.mounted) state = _read();
  }
}
