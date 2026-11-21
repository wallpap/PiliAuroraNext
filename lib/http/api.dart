import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/common/service_urls.dart';

abstract final class Api {
  static const String recommendListApp =
      '${HttpString.appBaseUrl}/x/v2/feed/index';
  static const String recommendListWeb =
      '/x/web-interface/wbi/index/top/feed/rcmd';

  static const String feedDislike = '${HttpString.appBaseUrl}/x/feed/dislike';
  static const String feedDislikeCancel =
      '${HttpString.appBaseUrl}/x/feed/dislike/cancel';

  static const String hotList = '/x/web-interface/popular';

  // https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/video/videostream_url.md
  static const String ugcUrl = '/x/player/wbi/playurl';

  static const String pgcUrl = '/pgc/player/web/v2/playurl';

  static const String pugvUrl = '/pugv/player/web/playurl';

  static const String tvPlayUrl = '/x/tv/playurl';

  static const String playInfo = '/x/player/wbi/v2';

  static const String videoIntro = '/x/web-interface/wbi/view';

  /// https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/video/action.md

  static const String likeVideo = '${HttpString.appBaseUrl}/x/v2/view/like';

  static const String pgcLikeCoinFav = '/pgc/season/episode/community';


  static const String dislikeVideo =
      '${HttpString.appBaseUrl}/x/v2/view/dislike';


  static const String coinVideo = '${HttpString.appBaseUrl}/x/v2/view/coin/add';


  static const String favResourceList = '/x/v3/fav/resource/list';

  static const String favVideo = '/x/v3/fav/resource/batch-deal';

  static const String unfavAll = '/x/v3/fav/resource/unfav-all';

  static const String copyFav = '/x/v3/fav/resource/copy';

  static const String moveFav = '/x/v3/fav/resource/move';

  static const String cleanFav = '/x/v3/fav/resource/clean';

  static const String sortFav = '/x/v3/fav/resource/sort';

  static const String sortFavFolder = '/x/v3/fav/folder/sort';



  static const String ugcTriple = '/x/web-interface/archive/like/triple';

  static const String pgcTriple = '/pgc/season/episode/like/triple';

  static const String favFolder = '/x/v3/fav/folder/created/list-all';

  static const String copyToview = '/x/v2/history/toview/copy';

  static const String moveToview = '/x/v2/history/toview/move';

  static const String relatedList = '/x/web-interface/archive/related';

  static const String relation = '/x/relation';

  static const String relations = '/x/relation/relations';

  static const String relationMod = '/x/relation/modify';


  static const String replyList = '/x/v2/reply';

  static const String replyReplyList = '/x/v2/reply/reply';

  static const String likeReply = '/x/v2/reply/action';

  static const String hateReply = '/x/v2/reply/hate';

  // https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/comment/action.md
  static const String replyAdd = '/x/v2/reply/add';

  // https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/comment/action.md
  static const String replyDel = '/x/v2/reply/del';

  static const String userStat = '/x/relation/stat';

  static const String myEmote = '/x/emote/user/panel/web';

  static const String emoteSettingPanel = '/x/emote/setting/panel';
  static const String myEmotePackages =
      '/bapis/main.community.interface.emote.EmoteService/MyPackages';
  static const String emotePackageDetail =
      '/bapis/main.community.interface.emote.EmoteService/PackageDetail';

  static const String addEmotePackage = '/x/emote/package/add';

  static const String removeEmotePackage = '/x/emote/package/remove';

  static const String userInfo = '/x/web-interface/nav';

  static const String userStatOwner = '/x/web-interface/nav/stat';

  static const String userFavFolder = '/x/v3/fav/folder/created/list';

  static const String favFolderInfo = '/x/v3/fav/folder/info';

  static const String addFolder = '/x/v3/fav/folder/add';

  static const String editFolder = '/x/v3/fav/folder/edit';

  static const String deleteFolder = '/x/v3/fav/folder/del';

  static const String followUp = '/x/polymer/web-dynamic/v1/portal';

  static const String dynUplist = '/x/polymer/web-dynamic/v1/uplist';

  static const String followDynamic = '/x/polymer/web-dynamic/v1/feed/all';

  static const String thumbDynamic = '/x/dynamic/feed/dyn/thumb';

  static const String seeYouLater = '/x/v2/history/toview/web';

  static const String historyList = '/x/web-interface/history/cursor';

  static const String pauseHistory = '/x/v2/history/shadow/set';

  static const String historyStatus = '/x/v2/history/shadow?jsonp=jsonp';

  static const String clearHistory = '/x/v2/history/clear';

  static const String delHistory = '/x/v2/history/delete';

  static const String searchHistory = '/x/web-interface/history/search';

  static const String hotSearchList =
      'https://s.search.bilibili.com/main/hotword';

  static const String searchDefault = '/x/web-interface/wbi/search/default';

  static const String searchSuggest = '/x/web-interface/suggest';

  static const String searchByType = '/x/web-interface/wbi/search/type';

  static const String searchAll = '/x/web-interface/wbi/search/all/v2';

  // https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/video/report.md
  static const String heartBeat = '/x/click-interface/web/heartbeat';

  static const String historyReport = '/x/v2/history/report';

  static const String roomEntryAction =
      '${HttpString.liveBaseUrl}/xlive/web-room/v1/index/roomEntryAction';

  static const String mediaListHistory = '/x/v1/medialist/history';

  static const String ab2c = '/x/player/pagelist';

  static const String pgcInfo = '/pgc/view/web/season';

  static const String pugvInfo = '/pugv/view/web/season';

  static const String episodeInfo = '/pgc/season/episode/web/info';

  static const String followings = '/x/relation/followings';

  static const followSearch = '/x/relation/followings/search';

  static const String fans = '/x/relation/fans';

  static const String liveList =
      '${HttpString.liveBaseUrl}/xlive/web-interface/v1/second/getUserRecommend';

  static const String liveRoomInfo =
      '${HttpString.liveBaseUrl}/xlive/web-room/v2/index/getRoomPlayInfo';

  static const String sendLiveMsg = '${HttpString.liveBaseUrl}/msg/send';

  static const String liveRoomInfoH5 =
      '${HttpString.liveBaseUrl}/xlive/web-room/v1/index/getH5InfoByRoom';

  static const String liveRoomDmPrefetch =
      '${HttpString.liveBaseUrl}/xlive/web-room/v1/dM/gethistory';

  static const String liveRoomDmToken =
      '${HttpString.liveBaseUrl}/xlive/web-room/v1/index/getDanmuInfo';

  static const String memberInfo = '/x/space/wbi/acc/info';

  static const String space = '${HttpString.appBaseUrl}/x/v2/space';

  static const String spaceArchive =
      '${HttpString.appBaseUrl}/x/v2/space/archive/cursor';

  static const String spaceChargingArchive =
      '${HttpString.appBaseUrl}/x/v2/space/archive/charging';

  static const String spaceSeason =
      '${HttpString.appBaseUrl}/x/v2/space/season/videos';

  static const String spaceSeries =
      '${HttpString.appBaseUrl}/x/v2/space/series';

  static const String spaceBangumi =
      '${HttpString.appBaseUrl}/x/v2/space/bangumi';

  static const String spaceArticle =
      '${HttpString.appBaseUrl}/x/v2/space/article';

  static const String spaceFav = '/x/v3/fav/folder/space';

  static const String seasonSeries = '/x/polymer/web-space/seasons_series_list';

  static const String memberCardInfo = '/x/web-interface/card';

  static const String searchArchive = '/x/space/wbi/arc/search';

  static const String dynSearch = '/x/polymer/web-dynamic/v1/feed/space/search';

  static const String memberDynamic = '/x/polymer/web-dynamic/v1/feed/space';

  static const String toViewLater = '/x/v2/history/toview/add';

  static const String toViewDel = '/x/v2/history/toview/v2/dels';

  static const String toViewClear = '/x/v2/history/toview/clear';

  static const String pgcAdd = '/pgc/web/follow/add';

  static const String pgcDel = '/pgc/web/follow/del';

  static const String pgcUpdate = '/pgc/web/follow/status/update';

  static const String favPgc = '/x/space/bangumi/follow/list';

  static const String blackLst = '/x/relation/blacks';

  static const String latestApp =
      'https://api.github.com/repos/${Constants.githubRepository}/releases';

  static const String onlineTotal = '/x/player/online/total';


  //https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/danmaku/action.md
  static const String shootDanmaku = '/x/v2/dm/post';

  static const String danmakuFilter = '/x/dm/filter/user';

  static const String danmakuFilterAdd = '/x/dm/filter/user/add';

  static const String danmakuFilterDel = '/x/dm/filter/user/del';

  static const String followUpTag = '/x/relation/tags';

  static const String addUsers = '/x/relation/tags/addUsers';

  static const String addSpecial = '/x/relation/tag/special/add';

  static const String delSpecial = '/x/relation/tag/special/del';

  static const String followUpGroup = '/x/relation/tag';

  static const String createFollowTag = '/x/relation/tag/create';

  static const String updateFollowTag = '/x/relation/tag/update';

  static const String delFollowTag = '/x/relation/tag/del';

  static const String msgUnread =
      '${HttpString.tUrl}/session_svr/v1/session_svr/single_unread';

  static const String msgFeedReply = '/x/msgfeed/reply';
  static const String msgFeedAt = '/x/msgfeed/at';
  static const String msgFeedLike = '/x/msgfeed/like';
  static const String msgSysNotify =
      '${HttpString.messageBaseUrl}/x/sys-msg/query_notify_list';

  static const String msgSysUpdateCursor =
      '${HttpString.messageBaseUrl}/x/sys-msg/update_cursor';


  static const String sessionList =
      '${HttpString.tUrl}/session_svr/v1/session_svr/get_sessions';

  static const String ackSessionMsg =
      '${HttpString.tUrl}/session_svr/v1/session_svr/update_ack';

  static const String dynamicDetail = '/x/polymer/web-dynamic/v1/detail';

  static const String aiConclusion = '/x/web-interface/view/conclusion/get';

  static const String getCaptcha =
      '${HttpString.passBaseUrl}/x/passport-login/captcha?source=main_web';

  static const String appSmsCode =
      '${HttpString.passBaseUrl}/x/passport-login/sms/send';

  static const String logInByAppSms =
      '${HttpString.passBaseUrl}/x/passport-login/login/sms';


  static const String loginByPwdApi =
      '${HttpString.passBaseUrl}/x/passport-login/oauth2/login';

  /// 根据https://ivan.hanloth.cn/archives/530/流程进行手机号验证
  static const String safeCenterGetInfo =
      '${HttpString.passBaseUrl}/x/safecenter/user/info';

  static const String preCapture =
      '${HttpString.passBaseUrl}/x/safecenter/captcha/pre';

  static const String safeCenterSmsCode =
      '${HttpString.passBaseUrl}/x/safecenter/common/sms/send';

  static const String safeCenterSmsVerify =
      '${HttpString.passBaseUrl}/x/safecenter/login/tel/verify';

  static const String oauth2AccessToken =
      '${HttpString.passBaseUrl}/x/passport-login/oauth2/access_token';

  static const getWebKey = '${HttpString.passBaseUrl}/x/passport-login/web/key';

  static const getTVCode =
      '${HttpString.passBaseUrl}/x/passport-tv-login/qrcode/auth_code';

  static const qrcodePoll =
      '${HttpString.passBaseUrl}/x/passport-tv-login/qrcode/poll';

  static const logout = '${HttpString.passBaseUrl}/login/exit/v2';

  static const getMemberViewApi = '/x/space/upstat';

  static const seasonArchives = '/x/polymer/web-space/seasons_archives_list';

  static const seriesArchives = '/x/series/archives';

  static const getUnreadDynamic = '/x/web-interface/dynamic/entrance';

  static const dynamicSpmPrefix = '${HttpString.spaceBaseUrl}/1/dynamic';

  static const activateBuvidApi = '/x/internal/gaia-gateway/ExClimbWuzhi';

  static const userSubFolder = '/x/v3/fav/folder/collected/list';

  static const favSeasonList = '/x/space/fav/season/list';

  static const String getRankApi = "/x/web-interface/ranking/v2";

  static const String pgcRank = "/pgc/web/rank/list";

  static const String pgcSeasonRank = "/pgc/season/rank/web/list";

  static const String unfavFolder = '/x/v3/fav/folder/unfav';

  static const String videoTags = '/x/web-interface/view/detail/tag';

  static const String reportMember =
      '${HttpString.spaceBaseUrl}/ajax/report/add';

  static const String removeMsg = '/session_svr/v1/session_svr/remove_session';

  static const String delSysMsg = '/x/sys-msg/del_notify_list';

  static const String delMsgfeed = '/x/msgfeed/del';

  static const String createDynamic = '/x/dynamic/feed/create/dyn';

  static const String removeDynamic = '/x/dynamic/feed/operate/remove';

  static const String uploadBfs = '/x/dynamic/feed/draw/upload_bfs';

  static const String uploadImage = '/x/upload/web/image';

  static const String videoRelation = '/x/web-interface/archive/relation';

  static const String favSeason = '/x/v3/fav/season/fav';

  static const String unfavSeason = '/x/v3/fav/season/unfav';

  static const String mediaList = '/x/v2/medialist/resource/list';

  static const String pgcIndexCondition = '/pgc/season/index/condition';

  static const String pgcIndexResult = '/pgc/season/index/result';

  static const String archiveNoteList = '/x/note/publish/list/archive';

  static const String noteList = '/x/note/list';

  static const String userNoteList = '/x/note/publish/list/user';

  static const String delNote = '/x/note/del';

  static const String delPublishNote = '/x/note/publish/del';

  static const String favArticle = '/x/polymer/web-dynamic/v1/opus/feed/fav';

  static const String communityAction =
      '/x/community/cosmo/interface/simple_action';

  static const String delFavArticle = '/x/article/favorites/del';

  static const String addFavArticle = '/x/article/favorites/add';

  static const String replyTop = '/x/v2/reply/top';

  static const String getCoin = '${HttpString.accountBaseUrl}/site/getCoin';

  static const String getLiveEmoticons =
      '${HttpString.liveBaseUrl}/xlive/web-ucenter/v2/emoticon/GetEmoticons';

  static const String pgcTimeline = '/pgc/web/timeline';

  static const String searchTrending = '/x/v2/search/trending/ranking';

  static const String setTopDyn = '/x/dynamic/feed/space/set_top';

  static const String rmTopDyn = '/x/dynamic/feed/space/rm_top';

  static const String searchRecommend =
      '${HttpString.appBaseUrl}/x/v2/search/recommend';

  static const String articleInfo = '/x/article/viewinfo';

  static const String dynamicReport = '/x/dynamic/feed/dynamic_report/add';

  // https://github.com/SocialSisterYi/bilibili-API-collect/pull/1242
  static const String articleView = '/x/article/view';

  static const String opusDetail = '/x/polymer/web-dynamic/v1/opus/detail';

  static const String gaiaVgateRegister = '/x/gaia-vgate/v1/register';

  static const String gaiaVgateValidate = '/x/gaia-vgate/v1/validate';

  static const String voteInfo = '/x/vote/vote_info';

  static const String doVote = '/x/vote/do_vote';

  static const String liveFeedIndex =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/index/feed';

  static const String liveFollow =
      '${HttpString.liveBaseUrl}/xlive/web-ucenter/user/following';

  static const String liveSecondList =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/second/getList';

  static const String msgSetNotice = '/x/msgfeed/notice';

  static const String liveAreaList =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/index/getAreaList';

  static const String liveRoomAreaList =
      '${HttpString.liveBaseUrl}/room/v1/Area/getList';

  static const String getLiveFavTag =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/second/get_fav_tag';

  static const String setLiveFavTag =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/second/set_fav_tag';

  static const String liveSearch =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/search_live';

  static const String topicTop =
      '${HttpString.appBaseUrl}/x/topic/web/details/top';

  static const String topicFeed = '/x/polymer/web-dynamic/v1/feed/topic';

  static const String topicFold = '/x/topic/web/details/fold';

  static const String spaceOpus = '/x/polymer/web-dynamic/v1/opus/feed/space';

  static const String articleList = '/x/article/list/web/articles';

  static const String setMsgDnd =
      '${HttpString.tUrl}/link_setting/v1/link_setting/set_msg_dnd';

  static const String imUserInfos = '${HttpString.tUrl}/x/im/user_infos';

  static const String getSessionSs =
      '${HttpString.tUrl}/link_setting/v1/link_setting/get_session_ss';

  static const String getMsgDnd =
      '${HttpString.tUrl}/link_setting/v1/link_setting/get_msg_dnd';

  static const String setPushSs =
      '${HttpString.tUrl}/link_setting/v1/link_setting/set_push_ss';

  static const String dynReserve = '/x/dynamic/feed/reserve/click';

  static const String spaceReserve = '/x/space/reserve';

  static const String spaceReserveCancel = '/x/space/reserve/cancel';

  static const String favPugv = '/pugv/app/web/favorite/page';

  static const String addFavPugv = '/pugv/app/web/favorite/add';

  static const String delFavPugv = '/pugv/app/web/favorite/del';

  static const String favTopicList = '/x/topic/web/fav/list';

  static const String addFavTopic = '/x/topic/fav/sub/add';

  static const String delFavTopic = '/x/topic/fav/sub/cancel';

  static const String likeTopic = '/x/topic/like';

  static const String pgcReviewL = '/pgc/review/long/list';

  static const String pgcReviewS = '/pgc/review/short/list';

  static const String pgcReviewLike = '/pgc/review/action/like';

  static const String pgcReviewDislike = '/pgc/review/action/dislike';

  static const String pgcReviewPost = '/pgc/review/short/post';

  static const String pgcReviewMod = '/pgc/review/short/modify';

  static const String pgcReviewDel = '/pgc/review/short/del';

  static const String topicPubSearch =
      '${HttpString.appBaseUrl}/x/topic/pub/search';

  static const String upowerRank = '/x/upower/up/member/rank/v2';

  static const String favFavFolder = '/x/v3/fav/folder/fav';

  static const String unfavFavFolder = '/x/v3/fav/folder/unfav';

  static const String coinArc = '${HttpString.appBaseUrl}/x/v2/space/coinarc';

  static const String likeArc = '${HttpString.appBaseUrl}/x/v2/space/likearc';

  static const String spaceSetting = '/x/space/setting/app';

  static const String spaceSettingMod = '/x/space/privacy/batch/modify';

  static const String vipExpAdd = '/x/vip/experience/add';

  static const String coinLog = '/x/member/web/coin/log';

  static const String dynTopicRcmd = '/x/topic/web/dynamic/rcmd';

  static const String matchInfo = '/x/esports/match/info';

  static const String dynPic = '/x/polymer/web-dynamic/v1/detail/pic';

  static const String msgLikeDetail = '/x/msgfeed/like_detail';

  static const String getLiveInfoByUser =
      '${HttpString.liveBaseUrl}/xlive/web-room/v1/index/getInfoByUser';

  static const String liveSetSilent =
      '${HttpString.liveBaseUrl}/liveact/user_silent';

  static const String addShieldKeyword =
      '${HttpString.liveBaseUrl}/xlive/web-ucenter/v1/banned/AddShieldKeyword';

  static const String delShieldKeyword =
      '${HttpString.liveBaseUrl}/xlive/web-ucenter/v1/banned/DelShieldKeyword';

  static const String liveShieldUser =
      '${HttpString.liveBaseUrl}/liveact/shield_user';

  static const String spaceComic = '${HttpString.appBaseUrl}/x/v2/space/comic';

  static const String spaceAudio = '/audio/music-service/web/song/upper';

  static const String spaceCheese = '/pugv/app/web/season/page';

  static const String dynMention = '/x/polymer/web-dynamic/v1/mention/search';

  static const String createVote = '/x/vote/create';

  static const String updateVote = '/x/vote/update';

  static const String createReserve = '/x/new-reserve/up/reserve/create';

  static const String updateReserve = '/x/new-reserve/up/reserve/update';

  static const String reserveInfo = '/x/new-reserve/up/reserve/info';

  static const String loginLog = '/x/member/web/login/log';

  static const String expLog = '/x/member/web/exp/log';

  static const String liveLikeReport =
      '${HttpString.liveBaseUrl}/xlive/app-ucenter/v1/like_info_v3/like/likeReportV3';

  static const String loginDevices =
      '${HttpString.passBaseUrl}/x/safecenter/user_login_devices';

  static const String bgmDetail = '/x/copyright-music-publicity/bgm/detail';

  static const String wishUpdate =
      '/x/copyright-music-publicity/bgm/wish/update';

  static const String bgmRecommend =
      '/x/copyright-music-publicity/bgm/recommend_list';

  static const String spaceShop =
      '${HttpString.mallBaseUrl}/community-hub/small_shop/feed/tab/item';

  static const String superChatMsg =
      '${HttpString.liveBaseUrl}/av/v1/SuperChat/getMessageList';

  static const String popularSeriesOne = '/x/web-interface/popular/series/one';

  static const String popularSeriesList =
      '/x/web-interface/popular/series/list';

  static const String popularPrecious = '/x/web-interface/popular/precious';

  static const String userRealName = '/x/member/app/up/realname';

  static const String liveDmReport =
      '${HttpString.liveBaseUrl}/xlive/web-ucenter/v1/dMReport/Report';

  static const String danmakuLike = '/x/v2/dm/thumbup/add';
  static const String danmakuLikeStats = '/x/v2/dm/thumbup/stats';

  static const String danmakuReport = '/x/dm/report/add';

  static const String danmakuRecall = '/x/dm/recall';

  static const String danmakuEditState = '/x/v2/dm/edit/state';

  static const String followedUp = '/x/relation/followings/followed_upper';

  static const String sameFollowing = '/x/relation/same/followings';

  static const String seasonStatus = '/pgc/view/web/season/user/status';

  static const String followeeVotes =
      '${HttpString.tUrl}/vote_svr/v1/vote_svr/followee_votes';

  static const String liveContributionRank =
      '${HttpString.liveBaseUrl}/xlive/general-interface/v1/rank/queryContributionRank';

  static const String liveGuardTopList =
      '${HttpString.liveBaseUrl}/xlive/app-room/v2/guardTab/topList';

  static const String superChatReport =
      '${HttpString.liveBaseUrl}/av/v1/SuperChat/report';

  static const String imMsgReport = '${HttpString.tUrl}/x/bplus/im/report/add';

  static const String dynPrivatePubSetting =
      '/x/dynamic/feed/dyn/private_pub_setting';

  static const String editDyn = '/x/dynamic/feed/edit/dyn';

  static const String replyInteraction =
      '/x/v2/reply/subject/interaction-status';

  static const String replySubjectModify = '/x/v2/reply/subject/modify';

  static const String videoshot = '/x/player/videoshot';

  static const String liveMedalWall =
      '${HttpString.liveBaseUrl}/xlive/web-ucenter/user/MedalWall';

  static const String memberGuard =
      '${HttpString.liveBaseUrl}/xlive/app-ucenter/v1/guard/MainGuardCardAll';

  static const String bubble = '/x/tribee/v1/dyn/all';

  static const String sortFollowTag = '/x/relation/tags/update_sort';

  static const String replyReport = '/x/v2/reply/report';

  static const String dynReaction = '/x/polymer/web-dynamic/v1/detail/reaction';

  static const String liveFeedback =
      '${HttpString.liveBaseUrl}/xlive/app-interface/v2/index/feedback';
}
