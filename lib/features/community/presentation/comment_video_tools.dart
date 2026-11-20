import 'dart:ui' show Image;

import 'package:pili_aurora_next/features/community/domain/comment.dart';

typedef CommentVideoShare = ({
  String url,
  String? title,
  String? cover,
  int? published,
  String? author,
});

typedef CommentVideoFrame = ({
  bool Function() isCurrent,
  Future<Image?> Function() read,
});

typedef CommentVideoTools = ({
  int? Function() durationMilliseconds,
  bool Function(Duration) seek,
  Duration? Function() position,
  CommentVideoFrame? Function() capture,
  CommentVideoShare? Function(CommentReply) share,
});
