import 'package:pili_aurora_next/models/user/danmaku_block.dart';

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

    dmRegExp = rules[1]
        .map(
          (e) => RegExp(
            _regExp.matchAsPrefix(e.filter)?.group(1) ?? e.filter,
            caseSensitive: false,
          ),
        )
        .toList();

    dmUid = rules[2].map((e) => e.filter).toSet();

    count = dmFilterString.length + dmRegExp.length + dmUid.length;
  }

  RuleFilter.empty();

  bool matches({required String midHash, required String content}) {
    return dmUid.contains(midHash) ||
        dmFilterString.any(content.contains) ||
        dmRegExp.any((pattern) => pattern.hasMatch(content));
  }
}
