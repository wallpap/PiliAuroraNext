import 'package:pili_aurora_next/pages/setting/models/model.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get recommendSettings => [
  const SwitchModel(
    title: '首页使用app端推荐',
    subtitle: '若web端推荐不太符合预期，可尝试切换至app端推荐',
    leading: Icon(Icons.model_training_outlined),
    setKey: SettingBoxKey.appRcmd,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '保留首页推荐刷新',
    subtitle: '下拉刷新时保留上次内容',
    leading: Icon(Icons.refresh),
    setKey: SettingBoxKey.enableSaveLastData,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '显示上次看到位置提示',
    subtitle: '保留上次推荐时，在上次刷新位置显示提示',
    leading: Icon(Icons.tips_and_updates_outlined),
    setKey: SettingBoxKey.savedRcmdTip,
    defaultVal: true,
  ),
  getVideoFilterSelectModel(
    title: '点赞率',
    suffix: '%',
    key: SettingBoxKey.minLikeRatioForRecommend,
    values: [0, 1, 2, 3, 4],
  ),
  getBanWordModel(
    title: '标题关键词过滤',
    key: SettingBoxKey.banWordForRecommend,
  ),
  getBanWordModel(
    title: 'App推荐/热门/排行榜: 视频分区关键词过滤',
    key: SettingBoxKey.banWordForZone,
  ),
  getVideoFilterSelectModel(
    title: '视频时长',
    suffix: 's',
    key: SettingBoxKey.minDurationForRcmd,
    values: [0, 30, 60, 90, 120],
  ),
  getVideoFilterSelectModel(
    title: '播放量',
    key: SettingBoxKey.minPlayForRcmd,
    values: [0, 50, 100, 500, 1000],
  ),
  const SwitchModel(
    title: '已关注UP豁免推荐过滤',
    subtitle: '推荐中已关注用户发布的内容不会被过滤',
    leading: Icon(Icons.favorite_border_outlined),
    setKey: SettingBoxKey.exemptFilterForFollowed,
    defaultVal: true,
  ),
  const SwitchModel(
    title: '过滤器也应用于详情页相关视频',
    subtitle: '其它（如热门视频、搜索等）均不受过滤器影响，无法豁免相关视频中的已关注UP',
    leading: Icon(Icons.explore_outlined),
    setKey: SettingBoxKey.applyFilterToRelatedVideos,
    defaultVal: true,
  ),
];
