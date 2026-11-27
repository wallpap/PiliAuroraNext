import 'package:pili_aurora_next/common/service_urls.dart';
import 'package:pili_aurora_next/core/text/number_format.dart';
import 'package:pili_aurora_next/core/time/date_format.dart';
import 'package:pili_aurora_next/core/time/duration_format.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/episode.dart';
import 'package:pili_aurora_next/features/playback/domain/pgc_detail/result.dart';
import 'package:pili_aurora_next/features/playback/domain/video_detail/data.dart';

final class VideoShareCardContent {
  const VideoShareCardContent._({
    required this.id,
    required this.url,
    required this.title,
    required this.kind,
    required this.subtitle,
    required this.publication,
    required this.duration,
    required this.metrics,
    required this.cover,
    this.author,
    this.avatar,
    this.artwork,
    this.followers,
  });

  factory VideoShareCardContent.video(
    VideoDetailData detail, {
    required String bvid,
    required int cid,
    int? followers,
  }) {
    final stat = detail.stat;
    final part = detail.pages?.where((part) => part.cid == cid).firstOrNull;
    final title = _firstText([detail.title]) ?? bvid;
    final prefix = _titlePrefix.firstMatch(title);
    return VideoShareCardContent._(
      id: bvid,
      url: '${HttpString.baseUrl}/video/$bvid/',
      title: title,
      kind: prefix?.group(1)?.trim() ?? '视频',
      subtitle: (detail.pages?.length ?? 0) > 1
          ? _firstText([part?.part]) ?? ''
          : '',
      publication: _date(detail.pubdate, '发布'),
      duration: _duration(part?.duration ?? detail.duration),
      metrics: _join([
        if (stat?.view case final value?) '${NumUtils.numFormat(value)}播放',
        if (stat?.like case final value?) '${NumUtils.numFormat(value)}点赞',
        if (stat?.danmaku case final value?) '${NumUtils.numFormat(value)}弹幕',
      ]),
      cover: _firstText([detail.pic]),
      author: _firstText([detail.owner?.name]),
      avatar: _firstText([detail.owner?.face]),
      followers: followers,
    );
  }

  factory VideoShareCardContent.episode(
    PgcInfoModel season, {
    required int epId,
    EpisodeItem? episode,
  }) {
    final movie = season.type == 2;
    final extraSection = movie
        ? season.section
              ?.where(
                (section) =>
                    section.episodes?.any(
                      (item) => (item.epId ?? item.id) == epId,
                    ) ??
                    false,
              )
              .firstOrNull
        : null;
    final feature =
        movie &&
        (extraSection == null ||
            (season.episodes?.any((item) => (item.epId ?? item.id) == epId) ??
                false));
    final kind = switch (season.type) {
      1 => '番剧',
      2 => '电影',
      3 => '纪录片',
      4 => '国创',
      5 => '电视剧',
      7 => '综艺',
      _ => '影视',
    };
    final episodeTitle = _firstText([
      episode?.longTitle,
      episode?.showTitle,
      extraSection?.title,
    ]);
    final index = _firstText([episode?.title]);
    final episodeLabel = switch (index) {
      final value? when _episodeNumber.hasMatch(value) =>
        '第$value${season.type == 1 || season.type == 4 ? '话' : '集'}',
      final value? when !(episodeTitle?.contains(value) ?? false) => value,
      _ => null,
    };
    final date = _date(episode?.pubTime, '上线');
    final cover = _firstText([episode?.cover, season.cover]);
    final duration = episode?.duration;
    return VideoShareCardContent._(
      id: 'ep$epId',
      url: '${HttpString.baseUrl}/bangumi/play/ep$epId',
      title: _firstText([season.title, season.seasonTitle]) ?? kind,
      kind: kind,
      subtitle: feature
          ? '正片'
          : [
              if (episodeLabel != null &&
                  !(episodeTitle?.contains(episodeLabel) ?? false))
                episodeLabel,
              ?episodeTitle,
            ].join('  '),
      publication: date.isEmpty && feature
          ? _seasonDate(season.publish?.pubTimeShow)
          : date,
      duration: _duration(duration == null ? null : duration ~/ 1000),
      metrics: (season.styles ?? []).take(3).join(' · '),
      cover: cover,
      artwork: movie ? _firstText([season.cover]) : null,
    );
  }

  final String id;
  final String url;
  final String title;
  final String kind;
  final String subtitle;
  final String publication;
  final String duration;
  final String metrics;
  final String? cover;
  final String? author;
  final String? avatar;
  final String? artwork;
  final int? followers;

  String get fileName => '$id-分享卡片';

  String get headline {
    final prefix = _titlePrefix.firstMatch(title);
    return prefix == null || id.startsWith('ep')
        ? title
        : title.substring(prefix.end).trim();
  }

  String get watchLabel => switch ((id.startsWith('ep'), kind, subtitle)) {
    (true, '电影', '正片') => '扫码在哔哩哔哩观看正片',
    (true, _, _) => '扫码在哔哩哔哩观看本集',
    _ => '扫码在哔哩哔哩观看',
  };

  String authorMetadata(int? followers) => _join([
    if (followers != null) '${NumUtils.numFormat(followers)} 粉丝',
    publication,
  ]);

  static final _titlePrefix = RegExp(r'^[「【]([^」】]{1,14})[」】]\s*(?=\S)');
  static final _episodeNumber = RegExp(r'^\d+(?:\.\d+)?$');
  static final _datePattern = RegExp(r'(\d{4})[-./年](\d{1,2})[-./月](\d{1,2})');

  static String? _firstText(Iterable<String?> values) => values.nonNulls
      .map((value) => value.trim())
      .where(
        (value) => value.isNotEmpty,
      )
      .firstOrNull;

  static String _join(Iterable<String> values) =>
      values.where((value) => value.isNotEmpty).join('  ·  ');

  static String _date(int? timestamp, String label) {
    if (timestamp == null || timestamp <= 0) return '';
    final seconds = timestamp >= 100000000000 ? timestamp ~/ 1000 : timestamp;
    final date = DateFormatUtils.format(
      seconds,
      format: DateFormatUtils.longFormat,
    );
    return "${date.replaceAll('-', '.')} $label";
  }

  static String _seasonDate(String? value) {
    final date = value == null ? null : _datePattern.firstMatch(value);
    if (date == null) return '';
    return "${date[1]}.${date[2]!.padLeft(2, '0')}.${date[3]!.padLeft(2, '0')} 上线";
  }

  static String _duration(int? seconds) => seconds != null && seconds > 0
      ? DurationUtils.formatDuration(seconds)
      : '';
}
