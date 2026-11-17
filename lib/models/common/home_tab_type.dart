import 'package:pili_aurora_next/models/common/enum_with_label.dart';
import 'package:pili_aurora_next/pages/hot/view.dart';
import 'package:pili_aurora_next/pages/live/view.dart';
import 'package:pili_aurora_next/pages/pgc/view.dart';
import 'package:pili_aurora_next/pages/rank/view.dart';
import 'package:pili_aurora_next/pages/rcmd/view.dart';
import 'package:material_ui/material_ui.dart';

enum HomeTabType implements EnumWithLabel {
  live('直播'),
  rcmd('推荐'),
  hot('热门'),
  rank('分区'),
  bangumi('番剧'),
  cinema('影视'),
  ;

  @override
  final String label;
  const HomeTabType(this.label);

  Widget get page => switch (this) {
    HomeTabType.live => const LivePage(),
    HomeTabType.rcmd => const RcmdPage(),
    HomeTabType.hot => const HotPage(),
    HomeTabType.rank => const RankPage(),
    HomeTabType.bangumi => const PgcPage(tabType: HomeTabType.bangumi),
    HomeTabType.cinema => const PgcPage(tabType: HomeTabType.cinema),
  };
}
