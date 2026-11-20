import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/application/dynamics_updates.dart';
import 'package:pili_aurora_next/features/community/data/dynamics_repository.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_draft.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';

final dynamicsPublishingProvider = Provider(
  (ref) => DynamicsPublishing(
    ref.read(dynamicsRepositoryProvider),
    ref.read(dynamicsUpdatesProvider),
  ),
);

class DynamicsPublishing {
  DynamicsPublishing(this._repository, this._updates);

  final DynamicsRepository _repository;
  final DynamicsUpdates _updates;
  final _editing = HashMap<Account, Set<String>>.identity();

  Future<LoadingState<String?>?> submit(
    Account account,
    DynamicDraft draft, {
    required Future<List?> Function() preparePictures,
    required bool Function() canSubmit,
  }) async {
    if (!identical(account, Accounts.main) || !canSubmit()) return null;

    final editId = draft.editId?.toString();
    final edits = editId == null
        ? null
        : _editing.putIfAbsent(account, () => {});
    if (edits != null && !edits.add(editId!)) {
      return const Error('正在编辑同一条动态，请稍候');
    }
    try {
      final pictures = await preparePictures();
      if (!identical(account, Accounts.main) || !canSubmit()) return null;

      final result = await _repository.publish(account, draft, pictures);
      if (result.isSuccess && identical(account, Accounts.main)) {
        if (result.data != null ||
            editId != null ||
            draft.publishTime == null) {
          _updates.published(account);
        }
      }
      return result;
    } finally {
      if (edits != null) {
        edits.remove(editId);
        if (edits.isEmpty) _editing.remove(account);
      }
    }
  }
}
