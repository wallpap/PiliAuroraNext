import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/domain/comments/reply_option_type.dart';

extension ReplyOptionIcon on ReplyOptionType {
  IconData get iconData => switch (this) {
    ReplyOptionType.allow => MdiIcons.commentTextOutline,
    ReplyOptionType.close => MdiIcons.commentOffOutline,
    ReplyOptionType.choose => MdiIcons.commentProcessingOutline,
  };
}
