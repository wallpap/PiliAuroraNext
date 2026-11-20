import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/core/uri/file_name.dart';

void main() {
  test('downloading or signing uses the path file name, even with a URL in the query', () {
    const url = 'https://example.test/media/image.png?redirect=https://cdn.test/other.jpg';

    expect(uriFileName(url), 'image.png');
    expect(uriFileName(url, fileExt: false), 'image');
  });
}
