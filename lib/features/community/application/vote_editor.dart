import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/account_draft_editor.dart';
import 'package:pili_aurora_next/features/community/data/vote_repository.dart';
import 'package:pili_aurora_next/features/community/domain/vote_draft.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/vote.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef VoteEditorQuery = ({Object owner, int? id});
final voteEditorProvider = NotifierProvider.autoDispose
    .family<VoteEditor, DraftEditorState<VoteDraft>, VoteEditorQuery>(
      VoteEditor.new,
    );

class VoteEditor extends AccountDraftEditor<VoteDraft, VoteInfo> {
  VoteEditor(this.query) : super(query.id);
  final VoteEditorQuery query;
  final _uploads = <Object, Object>{};
  List<Object?> get draft => state.draft.snapshot;
  int? get voteId => remoteId;
  @override
  VoteDraft initialDraft(DateTime now) => VoteDraft(
    deadline: DateTime(now.year, now.month, now.day + 1, now.hour, now.minute),
    options: [VoteOptionDraft(), VoteOptionDraft()],
  );
  @override
  Future<LoadingState<VoteDraft>> load(Account account, int id) =>
      ref.read(voteRepositoryProvider).load(account, id);
  @override
  Future<LoadingState<VoteInfo>> save(
    Account account,
    int? id,
    VoteDraft draft,
  ) => ref.read(voteRepositoryProvider).save(account, id, draft);
  @override
  int? savedId(VoteInfo result) => result.voteId;
  @override
  String? validate(VoteDraft draft) {
    if (draft.title.trim().isEmpty ||
        draft.title.length > 32 ||
        draft.options.length < 2 ||
        draft.options.length > 20 ||
        draft.options.any(
          (item) =>
              item.text.trim().isEmpty ||
              item.text.length > 20 ||
              (draft.type == 1 && item.image.isEmpty),
        ) ||
        draft.choices < 1 ||
        draft.choices > draft.options.length) {
      return '请填写完整的投票内容';
    }
    if (draft.deadline.difference(DateTime.now()).inSeconds < 300) {
      return '截止时间至少需要五分钟';
    }
    return null;
  }

  void optionText(Object id, String text) => update(
    (draft) => draft.copy(
      options: [
        for (final option in draft.options)
          option.id == id ? option.copy(text: text) : option,
      ],
    ),
  );
  void addOption() {
    if (state.draft.options.length < 20) {
      update(
        (draft) => draft.copy(options: [...draft.options, VoteOptionDraft()]),
      );
    }
  }

  void onDel(int index) {
    final options = state.draft.options;
    if (index < 0 || index >= options.length || options.length <= 2) return;
    _uploads.remove(options[index].id);
    update(
      (draft) => draft.copy(
        options: [...options]..removeAt(index),
        choices: draft.choices.clamp(1, options.length - 1),
      ),
    );
  }

  Future<LoadingState<void>> onUpload(Object id, String path) async {
    if (!isCurrent || !state.draft.options.any((option) => option.id == id)) {
      return const Error('选项或账号已更新');
    }
    final operation = _uploads[id] = Object();
    try {
      final result = await ref
          .read(voteRepositoryProvider)
          .upload(account, path);
      if (!isCurrent ||
          !identical(_uploads[id], operation) ||
          !state.draft.options.any((option) => option.id == id)) {
        return const Error('选项或账号已更新');
      }
      if (result case Success(:final response)
          when response != null && response.isNotEmpty) {
        update(
          (draft) => draft.copy(
            options: [
              for (final option in draft.options)
                option.id == id ? option.copy(image: response) : option,
            ],
          ),
        );
        return const Success(null);
      }
      return result is Error ? result : const Error('上传未返回图片地址');
    } catch (cause, stack) {
      return Error.fromException(cause, stack);
    } finally {
      if (identical(_uploads[id], operation)) _uploads.remove(id);
    }
  }
}
