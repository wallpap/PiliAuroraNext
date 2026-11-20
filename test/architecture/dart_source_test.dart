import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

void main() {
  test('classifies shared media UI and player widgets as presentation', () {
    expect(isPresentation('common/media/image_actions.dart'), isTrue);
    expect(isPresentation('common/media/screenshot.dart'), isTrue);
    expect(isPresentation('plugin/pl_player/widgets/new_widget.dart'), isTrue);
    expect(isPresentation('common/media/image_preview_source.dart'), isFalse);
    expect(
      isPresentation('plugin/pl_player/playback/native_player.dart'),
      isFalse,
    );
  });

  test('dependencies include conditional branches and exclude comments', () {
    final dependencies = sourceDependencies('''
// import 'comment.dart';
import 'default.dart' if (dart.library.io) 'native.dart' as api;
export 'public.dart' if (dart.library.js_interop) 'web.dart';
part 'generated.dart';
const example = "import 'string.dart';";
''');
    expect(dependencies, [
      'default.dart',
      'native.dart',
      'public.dart',
      'web.dart',
      'generated.dart',
    ]);
  });

  test('transport calls recognize aliases and whitespace, not source text', () {
    final calls = matchingStaticCalls(
      '''
void load() {
  api.MemberHttp
    .memberDynamic ('1');
  final example = 'MsgHttp.removeDynamic()';
  // DynamicsHttp.setTop('2');
}
''',
      {
        'MemberHttp.memberDynamic',
        'MsgHttp.removeDynamic',
        'DynamicsHttp.setTop',
      },
    );
    expect(calls, {'MemberHttp.memberDynamic'});
  });
}
