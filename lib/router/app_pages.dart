import 'package:pili_aurora_next/pages/article/view.dart';
import 'package:pili_aurora_next/pages/article_list/view.dart';
import 'package:pili_aurora_next/pages/audio/view.dart';
import 'package:pili_aurora_next/pages/blacklist/view.dart';
import 'package:pili_aurora_next/pages/bubble/view.dart';
import 'package:pili_aurora_next/pages/danmaku_block/view.dart';
import 'package:pili_aurora_next/pages/dlna/view.dart';
import 'package:pili_aurora_next/features/download/presentation/view.dart';
import 'package:pili_aurora_next/pages/dynamics/view.dart';
import 'package:pili_aurora_next/pages/dynamics_create_vote/view.dart';
import 'package:pili_aurora_next/pages/dynamics_detail/view.dart';
import 'package:pili_aurora_next/pages/dynamics_topic/view.dart';
import 'package:pili_aurora_next/pages/dynamics_topic_rcmd/view.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorites_page.dart';
import 'package:pili_aurora_next/features/favorites/presentation/folder_editor.dart';
import 'package:pili_aurora_next/features/favorites/presentation/favorite_detail_page.dart';
import 'package:pili_aurora_next/pages/follow/view.dart';
import 'package:pili_aurora_next/pages/follow_search/view.dart';
import 'package:pili_aurora_next/pages/follow_type/controller.dart';
import 'package:pili_aurora_next/pages/follow_type/view.dart';
import 'package:pili_aurora_next/features/history/presentation/history_page.dart';
import 'package:pili_aurora_next/pages/home/view.dart';
import 'package:pili_aurora_next/pages/hot/view.dart';
import 'package:pili_aurora_next/features/watch_later/presentation/later_page.dart';
import 'package:pili_aurora_next/pages/live_dm_block/view.dart';
import 'package:pili_aurora_next/pages/live_room/view.dart';
import 'package:pili_aurora_next/pages/login/view.dart';
import 'package:pili_aurora_next/pages/main/view.dart';
import 'package:pili_aurora_next/pages/main_reply/view.dart';
import 'package:pili_aurora_next/pages/match_info/view.dart';
import 'package:pili_aurora_next/pages/member/view.dart';
import 'package:pili_aurora_next/pages/member_dynamics/view.dart';
import 'package:pili_aurora_next/pages/member_guard/view.dart';
import 'package:pili_aurora_next/pages/member_profile/view.dart';
import 'package:pili_aurora_next/pages/member_search/view.dart';
import 'package:pili_aurora_next/pages/member_upower_rank/view.dart';
import 'package:pili_aurora_next/pages/member_video_web/archive/view.dart';
import 'package:pili_aurora_next/pages/member_video_web/season_series/view.dart';
import 'package:pili_aurora_next/pages/msg_feed_top/at_me/view.dart';
import 'package:pili_aurora_next/pages/msg_feed_top/like_detail/view.dart';
import 'package:pili_aurora_next/pages/msg_feed_top/like_me/view.dart';
import 'package:pili_aurora_next/pages/msg_feed_top/reply_me/view.dart';
import 'package:pili_aurora_next/pages/msg_feed_top/sys_msg/view.dart';
import 'package:pili_aurora_next/pages/music/view.dart';
import 'package:pili_aurora_next/pages/my_reply/view.dart';
import 'package:pili_aurora_next/pages/popular_precious/view.dart';
import 'package:pili_aurora_next/pages/popular_series/view.dart';
import 'package:pili_aurora_next/pages/search/view.dart';
import 'package:pili_aurora_next/pages/search_result/view.dart';
import 'package:pili_aurora_next/pages/search_trending/view.dart';
import 'package:pili_aurora_next/pages/setting/pages/bar_set.dart';
import 'package:pili_aurora_next/pages/setting/pages/color_select.dart';
import 'package:pili_aurora_next/pages/setting/pages/display_mode.dart';
import 'package:pili_aurora_next/pages/setting/pages/font_setting.dart';
import 'package:pili_aurora_next/pages/setting/pages/logs.dart';
import 'package:pili_aurora_next/pages/setting/pages/play_speed_set.dart';
import 'package:pili_aurora_next/pages/setting/view.dart';
import 'package:pili_aurora_next/pages/settings_search/view.dart';
import 'package:pili_aurora_next/pages/space_setting/view.dart';
import 'package:pili_aurora_next/pages/sponsor_block/view.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/subscriptions_page.dart';
import 'package:pili_aurora_next/features/subscriptions/presentation/subscription_detail_page.dart';
import 'package:pili_aurora_next/pages/video/view.dart';
import 'package:pili_aurora_next/pages/webview/view.dart';
import 'package:pili_aurora_next/pages/whisper/view.dart';
import 'package:pili_aurora_next/pages/whisper_detail/view.dart';
import 'package:get/get.dart';

class Routes {
  static final List<GetPage<dynamic>> getPages = [
    GetPage(name: '/', page: () => const MainApp()),
    // 首页(推荐)
    GetPage(name: '/home', page: () => const HomePage()),
    // 热门
    GetPage(name: '/hot', page: () => const HotPage()),
    // 视频详情
    GetPage(name: '/videoV', page: () => const VideoDetailPageV()),
    //
    GetPage(name: '/webview', page: () => const WebviewPage()),
    // 设置
    GetPage(name: '/setting', page: () => const SettingPage()),
    //
    GetPage(name: '/fav', page: () => const FavoritesPage()),
    //
    GetPage(name: '/favDetail', page: () => const FavoriteDetailPage()),
    // 稍后再看
    GetPage(name: '/later', page: () => const LaterPage()),
    // 历史记录
    GetPage(name: '/history', page: () => const HistoryPage()),
    // 搜索页面
    GetPage(name: '/search', page: () => const SearchPage()),
    // 搜索结果
    GetPage(name: '/searchResult', page: () => const SearchResultPage()),
    // 动态
    GetPage(name: '/dynamics', page: () => const DynamicsPage()),
    // 动态详情
    GetPage(name: '/dynamicDetail', page: () => const DynamicDetailPage()),
    // 关注
    GetPage(
      name: '/follow',
      page: () => FollowPage.fromArguments(Get.arguments),
    ),
    // 粉丝
    GetPage(
      name: '/fan',
      page: () => FollowTypePage.fromArguments(FollowKind.fans, Get.arguments),
    ),
    // 直播详情
    GetPage(name: '/liveRoom', page: () => const LiveRoomPage()),
    // 用户中心
    GetPage(name: '/member', page: () => const MemberPage()),
    GetPage(name: '/memberSearch', page: () => const MemberSearchPage()),
    //
    GetPage(name: '/blackListPage', page: () => const BlackListPage()),
    GetPage(name: '/colorSetting', page: () => const ColorSelectPage()),
    GetPage(name: '/fontSetting', page: () => const FontSettingPage()),
    // 屏幕帧率
    GetPage(name: '/displayModeSetting', page: () => const SetDisplayMode()),
    //
    GetPage(name: '/articlePage', page: () => const ArticlePage()),

    // 历史记录搜索
    GetPage(name: '/playSpeedSet', page: () => const PlaySpeedPage()),
    // 收藏搜索
    GetPage(
      name: '/favSearch',
      page: () => const FavoriteDetailPage(search: true),
    ),
    GetPage(
      name: '/historySearch',
      page: () => const HistoryPage(search: true),
    ),
    GetPage(name: '/laterSearch', page: () => const LaterPage(search: true)),
    GetPage(
      name: '/followSearch',
      page: () => FollowSearchPage.fromArguments(Get.arguments),
    ),
    // 消息页面
    GetPage(name: '/whisper', page: () => const WhisperPage()),
    // 私信详情
    GetPage(name: '/whisperDetail', page: () => const WhisperDetailPage()),
    // 回复我的
    GetPage(name: '/replyMe', page: () => const ReplyMePage()),
    // @我的
    GetPage(name: '/atMe', page: () => const AtMePage()),
    // 收到的赞
    GetPage(name: '/likeMe', page: () => const LikeMePage()),
    // 系统消息
    GetPage(name: '/sysMsg', page: () => const SysMsgPage()),
    // 登录页面
    GetPage(name: '/loginPage', page: () => const LoginPage()),
    // 用户动态
    GetPage(name: '/memberDynamics', page: () => const MemberDynamicsPage()),
    // 日志
    GetPage(name: '/logs', page: () => const LogsPage()),
    // 订阅
    GetPage(name: '/subscription', page: () => const SubPage()),
    // 订阅详情
    GetPage(name: '/subDetail', page: () => const SubDetailPage()),
    // 弹幕屏蔽管理
    GetPage(name: '/danmakuBlock', page: () => const DanmakuBlockPage()),
    GetPage(name: '/sponsorBlock', page: () => const SponsorBlockPage()),
    GetPage(name: '/createFav', page: () => const CreateFavPage()),
    GetPage(name: '/editProfile', page: () => const EditProfilePage()),
    GetPage(name: '/settingsSearch', page: () => const SettingsSearchPage()),
    GetPage(name: '/searchTrending', page: () => const SearchTrendingPage()),
    GetPage(
      name: '/dynTopic',
      page: () => DynTopicPage(
        topicId: Get.parameters['id']!,
        name: Get.parameters['name'] ?? '',
      ),
    ),
    GetPage(name: '/articleList', page: () => const ArticleListPage()),
    GetPage(name: '/barSetting', page: () => const BarSetPage()),
    GetPage(name: '/upowerRank', page: () => const UpowerRankPage()),
    GetPage(name: '/spaceSetting', page: () => const SpaceSettingPage()),
    GetPage(name: '/dynTopicRcmd', page: () => const DynTopicRcmdPage()),
    GetPage(name: '/matchInfo', page: () => const MatchInfoPage()),
    GetPage(name: '/msgLikeDetail', page: () => const LikeDetailPage()),
    GetPage(name: '/liveDmBlockPage', page: () => const LiveDmBlockPage()),
    GetPage(name: '/createVote', page: () => const CreateVotePage()),
    GetPage(name: '/musicDetail', page: () => const MusicDetailPage()),
    GetPage(name: '/popularSeries', page: () => const PopularSeriesPage()),
    GetPage(name: '/popularPrecious', page: () => const PopularPreciousPage()),
    GetPage(name: '/audio', page: () => const AudioPage()),
    GetPage(name: '/mainReply', page: () => const MainReplyPage()),
    GetPage(
      name: '/followed',
      page: () =>
          FollowTypePage.fromArguments(FollowKind.followed, Get.arguments),
    ),
    GetPage(
      name: '/sameFollowing',
      page: () => FollowTypePage.fromArguments(FollowKind.same, Get.arguments),
    ),
    GetPage(name: '/download', page: () => const DownloadPage()),
    GetPage(name: '/dlna', page: () => const DLNAPage()),
    GetPage(name: '/myReply', page: () => const MyReply()),
    GetPage(name: '/videoWeb', page: () => const MemberVideoWeb()),
    GetPage(name: '/ssWeb', page: () => const MemberSSWeb()),
    GetPage(name: '/memberGuard', page: () => const MemberGuard()),
    GetPage(
      name: '/bubble',
      page: () => BubblePage(tribeId: Get.arguments['id'].toString()),
    ),
  ];
}
