import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_comments.dart';

void main() {
  test('finds real comments, including interpolation and EOF', () {
    const source = r'''
/// Doc
const url = 'https://example.test';
const raw = r"/* not a comment */";
const multi = """
// not a comment
""";
const value = '${1 /* nested /* inner */ block */ + 2}';
const chained = /* one */ /* two */ 3; // on a code line
// EOF''';
    final comments = dartComments(source);
    expect(comments.map((comment) => comment.text), [
      '/// Doc',
      '/* nested /* inner */ block */',
      '/* one */',
      '/* two */',
      '// on a code line',
      '// EOF',
    ]);
    expect(comments.map((comment) => comment.line), [1, 7, 8, 8, 8, 9]);
    expect(dartComments('// Only').single.text, '// Only');
    expect(
      dartComments('// @dart=3.11\nconst value = 1;').single.text,
      '// @dart=3.11',
    );
  });

  test('grandfathers exact multiplicities rather than aggregate counts', () {
    const before = '// inherited\n// remove me\nconst value = 1;';
    const codeEdited = 'const value = 2;\r\n// inherited\r\n';
    expect(addedComments(before, codeEdited), isEmpty);
    expect(
      addedComments(before, '$codeEdited// replacement').single.text,
      '// replacement',
    );
    expect(
      addedComments(before, '$codeEdited// inherited').single.line,
      3,
    );
    expect(
      addedComments('', '// ignore_for_file: unused_import'),
      hasLength(1),
    );
    expect(
      addedComments('/* line\n   line */', '/* line\r\n   line */'),
      isEmpty,
    );
  });

  test('only physical comment-only lines count as removable lines', () {
    const source =
        '/* lead\r\n\r\n*/ const value = 1; // tail\r\n'
        '/* first */ /* second */\r\n'
        'const other = 2; /* start\r\nmiddle\r\nend */';
    final comments = dartComments(source);
    expect(comments.map((comment) => comment.endLine), [3, 3, 4, 4, 7]);
    expect(commentLineCounts(source, comments), (
      commentLines: 7,
      removableLines: 5,
    ));
  });

  test('covers repository Dart but keeps generated output read-only', () {
    for (final source in [
      'lib/app/new.dart',
      'test/architecture/comment_policy_test.dart',
      'tool/probes/check.dart',
      'tool/experiments/android/frame_plan_probe.dart.in',
    ]) {
      expect(isRepositoryDart(source), isTrue, reason: source);
      expect(isGeneratedDart(source), isFalse, reason: source);
    }
    for (final generated in [
      'lib/platform/android/bindings.g.dart',
      'lib/generated/bilibili/metadata.pb.dart',
      'lib/common/widgets/custom_icon.dart',
    ]) {
      expect(isRepositoryDart(generated), isTrue, reason: generated);
      expect(isGeneratedDart(generated), isTrue, reason: generated);
    }
    for (final excluded in [
      'lib/common/widgets/flutter/text_field/text_field.dart',
      'lib/scripts/build.ps1',
      'third_party/path/lib/path.dart',
    ]) {
      expect(isRepositoryDart(excluded), isFalse, reason: excluded);
    }
  });
}
