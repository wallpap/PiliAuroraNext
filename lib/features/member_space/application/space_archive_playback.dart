import 'package:pili_aurora_next/features/member_space/data/space_repository.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/member_space/domain/contribute_type.dart';
import 'package:pili_aurora_next/features/playback/domain/media/source_type.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_id.dart';

import 'package:pili_aurora_next/features/playback/domain/video_detail/dimension.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space_archive/item.dart';
import 'package:pili_aurora_next/features/media_catalog/domain/video_orientation.dart';

import 'package:pili_aurora_next/features/member_space/application/space_archive.dart';

typedef ArchivePlayback = ({
  int? aid,
  String bvid,
  int cid,
  Dimension? dimension,
  String? cover,
  String? title,
  bool isVertical,
  Map<String, dynamic> arguments,
});

Future<LoadingState<ArchivePlayback?>> resolveArchivePlayback(
  SpaceRepository repository,
  Account account,
  SpaceArchiveQuery query,
  SpaceArchiveState state,
  String? username,
  String? title,
) async {
  final button = state.button!;
  final params = Uri.tryParse(button.uri ?? '')?.queryParameters;
  final selected = query.season ?? query.series;
  final isVideo = query.type == ContributeType.video;
  Map<String, dynamic> arguments(Object oid) => {
    'sourceType': SourceType.archive,
    'mediaId': selected ?? query.mid,
    'oid': oid,
    'favTitle': '$username: ${title ?? button.text ?? '播放全部'}',
    if (query.series == null) 'count': ?state.count,
    if (selected != null) 'mediaType': params?['page_type'],
  };
  if (button.text == '继续播放' && button.uri?.isNotEmpty == true) {
    final aid = int.tryParse(params?['oid'] ?? '');
    if (aid == null || aid <= 0 || aid >= IdUtils.MAX_AID) {
      return const Error('继续播放地址无效，请刷新后重试');
    }
    final bvid = IdUtils.av2bv(aid);
    final result = await repository.videoPart(account, aid, bvid);
    if (result case Error error) return error;
    final part = result.dataOrNull;
    if (part == null) return const Error('暂无可播放的分 P，请刷新后重试');
    return Success((
      aid: aid,
      bvid: bvid,
      cid: part.cid,
      dimension: part.dimension,
      cover: null,
      title: null,
      isVertical: false,
      arguments: arguments('$aid')
        ..addAll({
          'desc': params?['desc'] == '1',
          'sortField': params?['sort_field'],
          'isContinuePlaying': true,
        }),
    ));
  }
  for (final item in state.loading.dataOrNull ?? const <SpaceArchiveItem>[]) {
    final bvid = item.bvid;
    final cid = item.cid;
    if (bvid == null ||
        cid == null ||
        cid <= 0 ||
        !IdUtils.bvRegexExact.hasMatch(bvid) ||
        !bvid.codeUnits.skip(3).every(IdUtils.invData.containsKey)) {
      continue;
    }
    final reverse =
        selected != null &&
        (isVideo ? state.order == .click : state.sort == .asc);
    return Success((
      aid: null,
      bvid: bvid,
      cid: cid,
      dimension: null,
      cover: item.cover,
      title: item.title,
      isVertical: item.uri?.isVerticalFromUri ?? false,
      arguments: arguments(IdUtils.bv2av(bvid))
        ..addAll({
          'desc': (query.season == null) != reverse,
          if (isVideo) 'sortField': state.order == .click ? 2 : 1,
        }),
    ));
  }
  return const Success(null);
}
