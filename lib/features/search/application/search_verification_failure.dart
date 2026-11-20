import 'package:pili_aurora_next/http/loading_state.dart';

class SearchVerificationRequired extends Error {
  const SearchVerificationRequired(this.voucher) : super('触发风控，请完成验证');
  final String voucher;
}
