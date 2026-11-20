import 'package:pili_aurora_next/features/community/domain/comments/reply_option_type.dart';

class DynamicDraft {
  DynamicDraft({
    required this.rawText,
    this.editId,
    this.repostId,
    this.videoId,
    this.videoType,
    this.publishTime,
    this.replyOption,
    this.isPrivate = false,
    this.topic,
    this.title,
    this.reserveId,
    List<Map<String, dynamic>>? richText,
  }) : richText = richText == null
           ? null
           : List.unmodifiable(richText.map(Map<String, dynamic>.unmodifiable));

  final String? rawText;
  final Object? editId;
  final Object? repostId;
  final int? videoId;
  final int? videoType;
  final DateTime? publishTime;
  final ReplyOptionType? replyOption;
  final bool isPrivate;
  final (int, String)? topic;
  final String? title;
  final Object? reserveId;
  final List<Map<String, dynamic>>? richText;
}
