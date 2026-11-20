import 'package:pili_aurora_next/features/media_catalog/domain/avatar.dart';

class OfficialVerify extends BaseOfficialVerify {
  String? spliceTitle;

  OfficialVerify.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    spliceTitle = json['splice_title'] as String?;
  }
}
