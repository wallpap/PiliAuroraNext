import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/content_discovery/presentation/recommendation_page.dart';
import 'package:pili_aurora_next/models/common/home_tab_type.dart';
import 'package:pili_aurora_next/pages/home/controller.dart';

/// 首页旧壳的意图适配；查询与 Widget 资源均由推荐模块持有。
class RcmdPage extends StatelessWidget {
  const RcmdPage({super.key});
  @override
  Widget build(BuildContext context) => RecommendationPage(
    register: (handle) => Get.isRegistered<HomeController>()
        ? Get.find<HomeController>().registerPage(HomeTabType.rcmd, handle)
        : () {},
  );
}
