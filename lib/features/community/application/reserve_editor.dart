import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/account_draft_editor.dart';
import 'package:pili_aurora_next/features/community/data/reserve_repository.dart';
import 'package:pili_aurora_next/features/community/domain/reserve.dart';
import 'package:pili_aurora_next/features/community/domain/reserve_draft.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

typedef ReserveEditorQuery = ({Object owner, int? id});
final reserveEditorProvider = NotifierProvider.autoDispose
    .family<ReserveEditor, DraftEditorState<ReserveDraft>, ReserveEditorQuery>(
      ReserveEditor.new,
    );

class ReserveEditor extends AccountDraftEditor<ReserveDraft, ReserveInfoData> {
  ReserveEditor(this.query) : super(query.id);
  final ReserveEditorQuery query;
  Object get draft => state.draft.snapshot;
  @override
  ReserveDraft initialDraft(DateTime now) => ReserveDraft(
    date: DateTime(now.year, now.month, now.day + 1, 20),
  );
  @override
  Future<LoadingState<ReserveDraft>> load(Account account, int id) =>
      ref.read(reserveRepositoryProvider).load(account, id);
  @override
  Future<LoadingState<ReserveInfoData>> save(
    Account account,
    int? id,
    ReserveDraft draft,
  ) => ref.read(reserveRepositoryProvider).save(account, id, draft);
  @override
  int? savedId(ReserveInfoData result) => result.id;
  @override
  String? validate(ReserveDraft draft) {
    if (draft.title.trim().isEmpty || draft.title.length > 14) {
      return '请填写预约标题，最多14字';
    }
    if (draft.subType != 0 && draft.subType != 1) return '请选择预约类型';
    if (!draft.date.isAfter(DateTime.now())) return '预约时间必须晚于当前时间';
    return null;
  }
}
