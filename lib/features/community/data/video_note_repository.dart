import 'package:dio/dio.dart';
import 'package:pili_aurora_next/features/community/domain/video_note.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/http/api.dart';
import 'package:pili_aurora_next/http/api_response.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

class VideoNoteRepository {
  static const _pageSize = 10;

  static Future<LoadingState<FeedPage<VideoNote, int?>>> list(
    Account account,
    int oid,
    int page,
  ) => Request().requestApi(
    Api.archiveNoteList,
    queryParameters: {
      'csrf': account.csrf,
      'oid': oid,
      'oid_type': 0,
      'pn': page,
      'ps': _pageSize,
    },
    options: Options(extra: {'account': account}),
    kind: ApiCallKind.query,
    decode: (body) {
      final data = body['data'] as Map<String, dynamic>;
      final rows = data['list'] as List<dynamic>? ?? const [];
      final total = (data['page'] as Map<String, dynamic>?)?['total'] as int?;
      return FeedPage(
        rows.cast<Map<String, dynamic>>().expand(_decodeNote),
        metadata: total,
        next: rows.isNotEmpty && (total == null || page * _pageSize < total)
            ? page + 1
            : null,
      );
    },
  );

  static Iterable<VideoNote> _decodeNote(Map<String, dynamic> row) sync* {
    final id = row['cvid'] as int?;
    if (id == null || id <= 0) return;
    final author = row['author'] as Map<String, dynamic>?;
    final vip = author?['vip_info'] as Map<String, dynamic>?;
    yield (
      id: id,
      summary: row['summary'] as String?,
      publishedAt: row['pubtime'] as String?,
      authorId: author?['mid'] as int?,
      authorName: author?['name'] as String?,
      authorAvatar: author?['face'] as String?,
      authorLevel: author?['level'] as int?,
      vipAuthor: (vip?['status'] as int? ?? 0) > 0 && vip?['type'] == 2,
      seniorAuthor: author?['is_senior_member'] == 1,
    );
  }
}
