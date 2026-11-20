import 'package:pili_aurora_next/features/member_space/domain/tab_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/data.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/tab2.dart';

/// 栏目从同一次空间响应派生，不能修改服务端返回的列表。
class SpaceTabs {
  SpaceTabs(SpaceData? data, MemberTabType preferred, {bool showShop = true})
    : tabs = List.unmodifiable(
        data == null
            ? _fallback
            : (data.tab2 ?? const <SpaceTab2>[])
                  .where(
                    (tab) => MemberTabType.values.any(
                      (type) =>
                          type.name == tab.param &&
                          (type != MemberTabType.shop || showShop),
                    ),
                  )
                  .skipWhile(
                    (tab) => data.hasItem != true && tab.param == 'home',
                  ),
      ),
      _preferred = preferred == MemberTabType.def ? null : preferred.name,
      _default = data?.defaultTab == 'video' ? 'contribute' : data?.defaultTab,
      _hasSeries =
          (data?.ugcSeason?.count ?? 0) > 0 ||
          data?.series?.item?.isNotEmpty == true;

  final List<SpaceTab2> tabs;
  final String? _preferred;
  final String? _default;
  final bool _hasSeries;

  int indexOf(String? param) => tabs.indexWhere((tab) => tab.param == param);

  int get initialIndex {
    final preferred = indexOf(_preferred);
    if (preferred >= 0) return preferred;
    final fallback = indexOf(_default);
    return fallback < 0 ? 0 : fallback;
  }

  late final List<SpaceTab2Item> contributions = List.unmodifiable([
    ..._items,
    if (_items.length > 1 && _hasSeries)
      const SpaceTab2Item(param: 'ugcSeason', title: '全部合集/列表'),
  ]);

  List<SpaceTab2Item> get _items {
    final index = indexOf('contribute');
    return index < 0 ? const [] : tabs[index].items ?? const [];
  }

  static const _fallback = [
    SpaceTab2(title: '动态', param: 'dynamic'),
    SpaceTab2(
      title: '投稿',
      param: 'contribute',
      items: [SpaceTab2Item(title: '视频', param: 'video')],
    ),
    SpaceTab2(title: '收藏', param: 'favorite'),
    SpaceTab2(title: '追番', param: 'bangumi'),
  ];
}

typedef SpaceWebArchive = ({int id, bool isSeason});

SpaceWebArchive? spaceWebArchive(SpaceTab2Item? item) {
  final id = item?.seasonId ?? item?.seriesId;
  return id == null ? null : (id: id, isSeason: item!.seasonId != null);
}
