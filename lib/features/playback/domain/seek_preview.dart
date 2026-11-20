import 'dart:math' show max, min;

typedef SeekPreviewSource = ({String bvid, int cid});

typedef SeekPreviewFrame = ({
  SeekPreviewAtlas atlas,
  String url,
  int column,
  int row,
  int columns,
  int rows,
});

final class SeekPreviewAtlas {
  SeekPreviewAtlas({
    required this.columns,
    required this.rows,
    required Iterable<String> images,
    required Iterable<int> timestamps,
  }) : _images = List.unmodifiable(images),
       _timestamps = List.unmodifiable(timestamps);

  final int columns;
  final int rows;
  final List<String> _images;
  final List<int> _timestamps;

  bool get isAvailable =>
      columns > 0 && rows > 0 && _images.isNotEmpty && _timestamps.isNotEmpty;

  SeekPreviewFrame? frameAt(int seconds) {
    if (!isAvailable) return null;
    var low = 0;
    var high = _timestamps.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_timestamps[middle] <= seconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final tilesPerImage = columns * rows;
    final index = min(max(0, low - 2), _images.length * tilesPerImage - 1);
    final tile = index % tilesPerImage;
    return (
      atlas: this,
      url: _images[index ~/ tilesPerImage],
      column: tile % columns,
      row: tile ~/ columns,
      columns: columns,
      rows: rows,
    );
  }
}
