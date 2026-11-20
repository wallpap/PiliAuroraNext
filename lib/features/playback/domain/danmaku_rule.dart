import 'package:pili_aurora_next/features/playback/domain/danmaku_block_rule.dart';

class RuleFilter {
  static final _regExp = RegExp(r'^/(.*)/$');

  List<String> dmFilterString = [];
  List<RegExp> dmRegExp = [];
  Set<String> dmUid = {};

  int count = 0;

  RuleFilter(this.dmFilterString, this.dmRegExp, this.dmUid, [int? count]) {
    this.count =
        count ?? dmFilterString.length + dmRegExp.length + dmUid.length;
  }

  RuleFilter.fromRuleTypeEntries(List<List<SimpleRule>> rules) {
    dmFilterString = rules[0].map((e) => e.filter).toList();

    dmRegExp = [
      for (final rule in rules[1]) ?compilePattern(rule.filter),
    ];

    dmUid = rules[2].map((e) => e.filter).toSet();

    count = dmFilterString.length + dmRegExp.length + dmUid.length;
  }

  RuleFilter.empty();

  static RegExp? compilePattern(String pattern) {
    try {
      return RegExp(
        _regExp.matchAsPrefix(pattern)?.group(1) ?? pattern,
        caseSensitive: false,
      );
    } on FormatException {
      return null;
    }
  }

  bool matches({required String midHash, required String content}) {
    return dmUid.contains(midHash) ||
        dmFilterString.any(content.contains) ||
        dmRegExp.any((pattern) => pattern.hasMatch(content));
  }
}
