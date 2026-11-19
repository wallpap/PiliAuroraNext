import 'package:canvas_danmaku/models/danmaku_content_item.dart'
    show DanmakuItemType;

DanmakuItemType danmakuPosition(int mode) => switch (mode) {
  4 => DanmakuItemType.bottom,
  5 => DanmakuItemType.top,
  7 => DanmakuItemType.special,
  _ => DanmakuItemType.scroll,
};
