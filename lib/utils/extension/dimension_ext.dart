import 'package:pili_aurora_next/generated/bilibili/app/archive/v1.pb.dart'
    show Dimension;

extension DimensionExt on Dimension {
  bool get isVertical => rotate == .ONE ? width > height : height > width;
}

extension StringExt on String {
  bool get isVerticalFromUri {
    final uri = Uri.tryParse(this);
    if (uri == null || !uri.hasQuery) return false;
    final Map<String, String> params;
    try {
      params = uri.queryParameters;
    } on FormatException {
      return false;
    }
    final width = int.tryParse(params['player_width'] ?? '');
    final height = int.tryParse(params['player_height'] ?? '');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return false;
    }
    return params['player_rotate'] == '1' ? width > height : height > width;
  }
}
