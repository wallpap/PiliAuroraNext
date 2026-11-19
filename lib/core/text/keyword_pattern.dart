class KeywordPattern {
  String? _previous;
  RegExp? _compiled;

  RegExp? resolve(String pattern) {
    if (_previous == pattern) return _compiled;
    _previous = pattern;
    try {
      return _compiled = pattern.isEmpty
          ? null
          : RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return _compiled = null;
    }
  }
}
