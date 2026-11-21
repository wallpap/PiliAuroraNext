import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';

typedef DartComment = ({
  int offset,
  int end,
  int line,
  int endLine,
  String text,
});

bool isRepositoryDart(String name) =>
    (name.endsWith('.dart') || name.endsWith('.dart.in')) &&
    !name.startsWith('third_party/') &&
    !name.startsWith('lib/common/widgets/flutter/');

bool isGeneratedDart(String name) =>
    name.endsWith('.g.dart') ||
    name.startsWith('lib/generated/') ||
    name == 'lib/common/widgets/custom_icon.dart';

List<DartComment> dartComments(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final comments = <DartComment>[];
  for (var token = parsed.unit.beginToken; ; token = token.next!) {
    for (
      Token? comment = token.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      comments.add((
        offset: comment.offset,
        end: comment.end,
        line: parsed.lineInfo.getLocation(comment.offset).lineNumber,
        endLine: parsed.lineInfo.getLocation(comment.end - 1).lineNumber,
        text: comment.lexeme,
      ));
    }
    if (token.isEof) break;
  }
  return comments;
}

List<DartComment> addedComments(String before, String after) {
  final allowed = <String, int>{};
  for (final comment in dartComments(before)) {
    final text = _commentKey(comment.text);
    allowed.update(text, (count) => count + 1, ifAbsent: () => 1);
  }
  return [
    for (final comment in dartComments(after))
      if (!_consume(allowed, _commentKey(comment.text))) comment,
  ];
}

String _commentKey(String text) => text.replaceAll('\r\n', '\n');

bool _consume(Map<String, int> allowed, String text) {
  final count = allowed[text] ?? 0;
  if (count == 0) return false;
  allowed[text] = count - 1;
  return true;
}

({int commentLines, int removableLines}) commentLineCounts(
  String source,
  List<DartComment> comments,
) {
  final touched = <int>{};
  final uncommented = StringBuffer();
  final nonNewline = RegExp(r'[^\r\n]+');
  var cursor = 0;
  for (final comment in comments) {
    for (var line = comment.line; line <= comment.endLine; line++) {
      touched.add(line);
    }
    uncommented
      ..write(source.substring(cursor, comment.offset))
      ..write(comment.text.replaceAll(nonNewline, ' '));
    cursor = comment.end;
  }
  uncommented.write(source.substring(cursor));
  final lines = const LineSplitter().convert(uncommented.toString());
  return (
    commentLines: touched.length,
    removableLines: touched
        .where((line) => lines[line - 1].trim().isEmpty)
        .length,
  );
}

void main(List<String> arguments) {
  try {
    switch (arguments) {
      case []:
        _check('HEAD');
      case ['--check', final base]:
        _check(base);
      case ['--stats'] || ['--inventory']:
        _inventory(arguments.first, '.');
      case [final mode, final selection]
          when mode == '--stats' || mode == '--inventory':
        _inventory(
          mode,
          selection.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), ''),
        );
      default:
        stderr.writeln(
          '用法：tool/check_comments.dart [--check <Git 基线> | '
          '--stats [路径] | --inventory [路径]]',
        );
        exitCode = 64;
    }
  } on Exception catch (error) {
    stderr.writeln('注释检查无法完成：$error');
    exitCode = 2;
  }
}

Iterable<String> _paths(List<String> arguments) =>
    _git(arguments).split('\u0000').where(isRepositoryDart);

String _git(List<String> arguments) {
  final result = Process.runSync('git', arguments, stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      [arguments.first],
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }
  return result.stdout as String;
}

const _untracked = ['ls-files', '-z', '--others', '--exclude-standard'];

bool _isFile(String name) =>
    FileSystemEntity.typeSync(name, followLinks: false) ==
    FileSystemEntityType.file;

void _check(String revision) {
  final base = _git([
    'rev-parse',
    '--verify',
    '--end-of-options',
    '$revision^{commit}',
  ]).trim();
  final changed = {
    ..._paths([
      'diff',
      '--name-only',
      '-z',
      '--no-renames',
      '--diff-filter=ACMRT',
      base,
    ]),
    ..._paths(_untracked),
  }.where((name) => !isGeneratedDart(name) && _isFile(name)).toList()..sort();
  final baseFiles = _paths(['ls-tree', '-r', '--name-only', '-z', base])
      .toSet();
  var violations = 0;
  for (final name in changed) {
    final before = baseFiles.contains(name)
        ? _git(['show', '--no-textconv', '$base:$name'])
        : '';
    for (final comment in addedComments(
      before,
      File(name).readAsStringSync(),
    )) {
      stderr.writeln('$name:${comment.line}: 不允许新增或改写注释。');
      violations++;
    }
  }
  if (violations != 0) {
    stderr.writeln('注释棘轮检查失败：发现 $violations 条新增或改写的注释。');
    exitCode = 1;
    return;
  }
  stdout.writeln('Dart 注释棘轮检查通过（${changed.length} 个有变更的手写文件）。');
}

void _inventory(String mode, String selection) {
  final files =
      _paths([
          'ls-files',
          '-z',
          '--cached',
          '--others',
          '--exclude-standard',
        ]).toSet().where((name) {
          return (selection == '.' ||
                  name == selection ||
                  name.startsWith('$selection/')) &&
              _isFile(name);
        }).toList()
        ..sort();
  if (files.isEmpty) throw FormatException('范围内没有第一方 Dart 文件：$selection');
  var tokens = 0;
  var commentLines = 0;
  var removableLines = 0;
  var generatedLines = 0;
  for (final name in files) {
    final source = File(name).readAsStringSync();
    final comments = dartComments(source);
    final counts = commentLineCounts(source, comments);
    tokens += comments.length;
    commentLines += counts.commentLines;
    if (isGeneratedDart(name)) {
      generatedLines += counts.removableLines;
    } else {
      removableLines += counts.removableLines;
    }
    if (mode == '--inventory') {
      for (final comment in comments) {
        stdout.writeln(
          jsonEncode({
            'path': name,
            'line': comment.line,
            'endLine': comment.endLine,
            'text': comment.text,
            if (isGeneratedDart(name)) 'protected': 'generated',
          }),
        );
      }
    }
  }
  if (mode == '--stats') {
    stdout.writeln(
      '$selection：${files.length} 个文件，$tokens 个注释 token，'
      '$commentLines 个含注释行，手写文件最多减少 $removableLines 行'
      '（另有 $generatedLines 行纯生成注释）。',
    );
  }
}
