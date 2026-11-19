import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/data/video_note_repository.dart';
import 'package:pili_aurora_next/features/community/domain/video_note.dart';
import 'package:pili_aurora_next/features/content_library/application/paged_feed.dart';
import 'package:pili_aurora_next/services/account_providers.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

typedef VideoNotesQuery = ({Object owner, int oid});

final videoNotesProvider = AsyncNotifierProvider.autoDispose
    .family<VideoNotes, FeedState<VideoNote, int?>, VideoNotesQuery>(
      VideoNotes.new,
      retry: (_, _) => null,
    );

class VideoNotes extends PagedFeed<VideoNote, int?> {
  VideoNotes(this.query);
  final VideoNotesQuery query;

  @override
  bool get requiresLogin => false;

  @override
  bool get endOnEmptyBudget => false;

  @override
  Account watchAccount() => ref.watch(mainAccountProvider);

  @override
  bool ownsAccount(Account account) =>
      identical(account, ref.read(mainAccountProvider));

  @override
  int itemKey(VideoNote item) => item.id;

  @override
  int? mergeMetadata(int? previous, int? next) => next ?? previous;

  @override
  Future<FeedPage<VideoNote, int?>> fetch(
    Account account,
    Object? cursor,
  ) async => (await VideoNoteRepository.list(
    account,
    query.oid,
    cursor as int? ?? 1,
  )).data;
}
