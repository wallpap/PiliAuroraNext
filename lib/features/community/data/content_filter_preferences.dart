import 'package:pili_aurora_next/core/text/keyword_pattern.dart';
import 'package:pili_aurora_next/features/community/domain/dynamics/result.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

typedef ContentFilter = ({RegExp? keywords, bool hideGoods});

abstract final class ContentFilterPreferences {
  static final _comments = KeywordPattern();
  static final _dynamics = KeywordPattern();

  static ContentFilter comments() => (
    keywords: _comments.resolve(Pref.banWordForReply),
    hideGoods: Pref.antiGoodsReply,
  );

  static DynamicsDecodeOptions dynamics() => DynamicsDecodeOptions(
    keywords: _dynamics.resolve(Pref.banWordForDyn),
    hideGoods: Pref.antiGoodsDyn,
    showInteraction: Pref.showDynInteraction,
    showDispute: Pref.showDynDispute,
    showDecoration: Pref.showDecorate,
  );
}
