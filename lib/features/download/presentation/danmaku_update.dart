import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/download/application/download_service.dart';
import 'package:pili_aurora_next/services/logger.dart';

/// 固定本次选择，逐项消费更新结果；失败项由页面保留以便重试。
class DownloadDanmakuUpdate {
  bool busy = false;

  Future<Set<T>> run<T>({
    required Future<LoadingState<void>> Function(T) update,
    required Iterable<T> entries,
    required bool Function() isCurrent,
  }) async {
    if (busy || !isCurrent()) return {};
    final snapshot = entries.toSet();
    if (snapshot.isEmpty) return {};
    busy = true;
    final updated = <T>{};
    Error? failure;
    try {
      for (final entry in snapshot) {
        if (!isCurrent()) break;
        try {
          final result = await update(entry);
          if (result.isSuccess) {
            updated.add(entry);
          } else if (result is Error && result is! DownloadCancelled) {
            failure ??= result;
          }
        } catch (error, stack) {
          logger.w('弹幕更新失败', error: error.runtimeType, stackTrace: stack);
          failure ??= Error('弹幕更新失败，请重试', cause: error, stackTrace: stack);
        }
      }
      if (isCurrent()) {
        if (failure != null) {
          failure.toast();
        } else if (updated.length == snapshot.length) {
          SmartDialog.showToast('更新成功');
        }
      }
      return updated;
    } finally {
      busy = false;
    }
  }
}
