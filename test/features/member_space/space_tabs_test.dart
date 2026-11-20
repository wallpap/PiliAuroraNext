import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/features/member_space/domain/space_tabs.dart';
import 'package:pili_aurora_next/features/member_space/domain/tab_type.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/data.dart';
import 'package:pili_aurora_next/features/member_space/domain/profiles/space/tab2.dart';

void main() {
  test('空间入口保留栏目优先级，不修改远端默认值', () {
    final data = SpaceData(
      defaultTab: 'video',
      tab2: const [
        SpaceTab2(param: 'home'),
        SpaceTab2(param: 'dynamic'),
        SpaceTab2(param: 'contribute'),
        SpaceTab2(param: 'unknown'),
      ],
    );
    final tabs = SpaceTabs(data, MemberTabType.def);
    expect(tabs.tabs.map((tab) => tab.param), ['dynamic', 'contribute']);
    expect(tabs.initialIndex, 1);
    expect(SpaceTabs(data, MemberTabType.dynamic).initialIndex, 0);
    expect(data.defaultTab, 'video');
    expect(data.tab2, hasLength(4));
  });

  test('Web 入口区分普通投稿、合集和系列', () {
    expect(spaceWebArchive(const SpaceTab2Item(param: 'video')), isNull);
    expect(spaceWebArchive(const SpaceTab2Item(seasonId: 7)), (
      id: 7,
      isSeason: true,
    ));
    expect(spaceWebArchive(const SpaceTab2Item(seriesId: 9)), (
      id: 9,
      isSeason: false,
    ));
    expect(
      SpaceTabs(null, MemberTabType.def).contributions.single.param,
      'video',
    );
  });
}
