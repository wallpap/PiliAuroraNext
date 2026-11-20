import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_cover_prefetch.dart';

void main() {
  testWidgets('预取串行进行，换行或隐藏后撤销尚未开始的封面', (tester) async {
    final requests = <String, Completer<void>>{};
    final prefetch = RecommendationCoverPrefetch((url) {
      return (requests[url] = Completer<void>()).future;
    })..update(['old-first', 'old-second']);
    await tester.pump(const Duration(milliseconds: 120));
    expect(requests.keys, ['old-first']);

    prefetch.update(['new-first', 'new-second']);
    await tester.pump(const Duration(milliseconds: 120));
    expect(requests.keys, ['old-first']);
    requests['old-first']!.complete();
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(requests.keys, ['old-first', 'new-first']);

    prefetch.clear();
    requests['new-first']!.complete();
    await tester.pump(const Duration(milliseconds: 120));
    expect(requests.keys, ['old-first', 'new-first']);
  });
}
