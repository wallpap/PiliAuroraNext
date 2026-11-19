import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/view_insets_safe_area.dart';
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/pages/setting/models/model.dart';
import 'package:pili_aurora_next/pages/setting/models/setting_type.dart';
import 'package:pili_aurora_next/utils/grid.dart';
import 'package:pili_aurora_next/utils/rate_limiter.dart';
import 'package:pili_aurora_next/utils/waterfall.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final _textEditingController = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 200));
  List<SettingsModel> _results = const [];
  late List<SettingsModel> _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = [
      for (final type in SettingType.values)
        if (type != SettingType.webdavSetting)
          for (final item in type.settings(context)) ...item.searchableItems,
    ];
  }

  void _search(String value) {
    final query = value.toLowerCase();
    setState(() {
      _results = query.isEmpty
          ? const []
          : _settings
                .where(
                  (item) =>
                      item.effectiveTitle.toLowerCase().contains(query) ||
                      item.effectiveSubtitle?.toLowerCase().contains(query) ==
                          true,
                )
                .toList();
    });
  }

  @override
  void dispose() {
    _debouncer.cancel();
    _textEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () {
              if (_textEditingController.text.isNotEmpty) {
                _debouncer.cancel();
                _textEditingController.clear();
                _search('');
              } else {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.clear),
          ),
          const SizedBox(width: 10),
        ],
        title: TextField(
          autofocus: true,
          controller: _textEditingController,
          textAlignVertical: TextAlignVertical.center,
          onChanged: (value) => _debouncer.run(() => _search(value)),
          decoration: const InputDecoration(
            isDense: true,
            hintText: '搜索',
            visualDensity: .standard,
            border: InputBorder.none,
          ),
        ),
      ),
      body: ViewInsetsSafeArea(
        child: CustomScrollView(
          slivers: [
            ViewSliverSafeArea(
              sliver: _results.isEmpty
                  ? const HttpError()
                  : SliverWaterfallFlow(
                      gridDelegate:
                          SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: Grid.smallCardWidth * 2,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (_, index) => _results[index].widget,
                        childCount: _results.length,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
