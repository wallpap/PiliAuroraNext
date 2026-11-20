import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/sponsor_block/application/sponsor_block_settings.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/skip_type.dart';
import 'package:pili_aurora_next/features/sponsor_block/domain/segment_response/user_info.dart';
import 'package:pili_aurora_next/pages/setting/slide_color_picker.dart';
import 'package:pili_aurora_next/common/input/filtering_text.dart';
import 'package:pili_aurora_next/router/page_utils.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/app_popup_menu_item.dart';

class SponsorBlockPage extends ConsumerStatefulWidget {
  const SponsorBlockPage({super.key});

  @override
  ConsumerState<SponsorBlockPage> createState() => _SponsorBlockPageState();
}

class _SponsorBlockPageState extends ConsumerState<SponsorBlockPage> {
  final _url = 'https://github.com/hanydd/BilibiliSponsorBlock';
  final _textController = TextEditingController();
  SponsorBlockSettings get _settings => ref.read(sponsorBlockSettingsProvider);
  SponsorBlockSettingsNotifier get _actions =>
      ref.read(sponsorBlockSettingsProvider.notifier);

  Future<void> _save(
    Future<LoadingState<void>?> pending, {
    BuildContext? dialogContext,
  }) async {
    final result = await pending;
    if (!mounted) return;
    if (result is Error) {
      result.toast();
      return;
    }
    if (result?.isSuccess == true &&
        dialogContext != null &&
        dialogContext.mounted &&
        ModalRoute.of(dialogContext)?.isCurrent == true) {
      Navigator.of(dialogContext).pop();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Widget _blockLimitItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        onTap: () {
          _textController.text = _settings.limit.toString();
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('最短片段时长', style: titleStyle),
              content: TextFormField(
                keyboardType: const .numberWithOptions(decimal: true),
                controller: _textController,
                autofocus: true,
                decoration: const InputDecoration(suffixText: 's'),
                inputFormatters: FilteringText.decimal,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    '取消',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () => _save(
                    _actions.saveLimit(double.tryParse(_textController.text)),
                    dialogContext: dialogContext,
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
        title: Text('最短片段时长', style: titleStyle),
        subtitle: Text(
          '忽略短于此时长的片段',
          style: subTitleStyle,
        ),
        trailing: Text(
          '${_settings.limit}s',
          style: const TextStyle(fontSize: 13),
        ),
      );
    },
  );

  Widget _aboutItem(TextStyle titleStyle, TextStyle subTitleStyle) => ListTile(
    dense: true,
    title: Text('关于空降助手', style: titleStyle),
    subtitle: Text(_url, style: subTitleStyle),
    onTap: () => PageUtils.launchURL(_url),
  );

  Widget _userIdItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        title: Text('用户ID', style: titleStyle),
        subtitle: Text(_settings.identity.userId, style: subTitleStyle),
        onTap: () {
          final key = GlobalKey<FormFieldState<String>>();
          _textController.text = _settings.identity.userId;
          showDialog(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text('用户ID', style: titleStyle),
                content: TextFormField(
                  key: key,
                  minLines: 1,
                  maxLines: 4,
                  autofocus: true,
                  controller: _textController,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\d]+')),
                  ],
                  decoration: const InputDecoration(errorMaxLines: 2),
                  validator: (value) {
                    if ((value?.length ?? -1) < 30) {
                      return '用户ID要求至少为30个字符长度的纯字符串';
                    }
                    return null;
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => _save(
                      _actions.randomizeUserId(),
                      dialogContext: dialogContext,
                    ),
                    child: const Text('随机'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (key.currentState?.validate() != true) return;
                      _save(
                        _actions.saveUserId(_textController.text),
                        dialogContext: dialogContext,
                      );
                    },
                    child: const Text('确定'),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );

  Widget _blockToastItem(TextStyle titleStyle) => Builder(
    builder: (context) {
      Future<void> update() => _save(_actions.saveToast(!_settings.toast));

      return ListTile(
        dense: true,
        onTap: update,
        title: Text(
          '显示跳过Toast',
          style: titleStyle,
        ),
        trailing: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.8,
          child: Switch(
            value: _settings.toast,
            onChanged: (val) => update(),
          ),
        ),
      );
    },
  );

  Widget _blockTrackItem(
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      Future<void> update() => _save(_actions.saveTracking(!_settings.track));

      return ListTile(
        dense: true,
        onTap: update,
        title: Text(
          '跳过次数统计跟踪',
          style: titleStyle,
        ),
        subtitle: Text(
          // from origin extension
          '此功能追踪您跳过了哪些片段，让用户知道他们提交的片段帮助了多少人。同时点赞会作为依据，确保垃圾信息不会污染数据库。在您每次跳过片段时，我们都会向服务器发送一条消息。希望大家开启此项设置，以便得到更准确的统计数据。:)',
          style: subTitleStyle,
        ),
        trailing: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.8,
          child: Switch(
            value: _settings.track,
            onChanged: (val) => update(),
          ),
        ),
      );
    },
  );

  Widget _blockUserInfo(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => ListTile(
    dense: true,
    onTap: () => _actions.refreshUserInfo(),
    title: Text(
      '您的信息',
      style: titleStyle,
    ),
    subtitle: switch (_settings.userInfo) {
      Loading() => const SizedBox.shrink(),
      Success<UserInfo>(:final response) => Text(
        response.toString(),
        style: subTitleStyle,
      ),
      Error error => Text(
        error.toString(),
        style: subTitleStyle.copyWith(color: theme.colorScheme.error),
      ),
    },
  );

  Widget _blockServerItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        onTap: () {
          _textController.text = _settings.identity.server;
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('服务器地址', style: titleStyle),
              content: TextFormField(
                keyboardType: TextInputType.url,
                controller: _textController,
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => _save(
                    _actions.resetServer(),
                    dialogContext: dialogContext,
                  ),
                  child: const Text('重置'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _save(
                    _actions.saveServer(_textController.text),
                    dialogContext: dialogContext,
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
        title: Text(
          '服务器地址',
          style: titleStyle,
        ),
        subtitle: Text(
          _settings.identity.server,
          style: subTitleStyle,
        ),
      );
    },
  );

  Widget _serverStatusItem(ThemeData theme, TextStyle titleStyle) {
    String status;
    Color? color;
    switch (_settings.uptime) {
      case Loading():
        status = '检查中';
      case Success():
        status = '正常';
        color = theme.colorScheme.primary;
      case Error error:
        status = error.toString();
        color = theme.colorScheme.error;
    }
    return ListTile(
      dense: true,
      onTap: () => _actions.refreshUptime(),
      title: Text('服务器状态', style: titleStyle),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: Text(
          status,
          textAlign: TextAlign.end,
          style: TextStyle(fontSize: 13, color: color),
        ),
      ),
    );
  }

  void onSelectColor(
    BuildContext context,
    SegmentType category,
    Color color,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        title: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Color Picker ',
                style: TextStyle(fontSize: 15),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                style: const TextStyle(fontSize: 13, height: 1),
              ),
              TextSpan(
                text: ' ${category.title}',
                style: const TextStyle(fontSize: 13, height: 1),
              ),
            ],
          ),
        ),
        content: SlideColorPicker(
          color: color,
          showResetBtn: true,
          onChanged: (color) => _save(_actions.saveColor(category, color)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sponsorBlockSettingsProvider);
    final theme = Theme.of(context);

    const titleStyle = TextStyle(fontSize: 15);

    final subTitleStyle = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.outline,
    );

    final divider = Divider(
      height: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    );

    final sliverDivider = SliverToBoxAdapter(child: divider);

    final dividerL = SliverToBoxAdapter(
      child: Divider(
        thickness: 16,
        color: theme.colorScheme.outline.withValues(alpha: 0.1),
      ),
    );

    return SimpleScaffold(
      appBar: AppBar(title: const Text('空降助手')),
      body: CustomScrollView(
        slivers: [
          dividerL,
          SliverToBoxAdapter(child: _serverStatusItem(theme, titleStyle)),
          dividerL,
          SliverToBoxAdapter(
            child: _blockLimitItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(child: _blockToastItem(titleStyle)),
          sliverDivider,
          SliverToBoxAdapter(child: _blockTrackItem(titleStyle, subTitleStyle)),
          sliverDivider,
          SliverToBoxAdapter(
            child: _blockUserInfo(theme, titleStyle, subTitleStyle),
          ),
          dividerL,
          SliverList.separated(
            itemCount: SegmentType.values.length,
            itemBuilder: (context, index) =>
                _buildItem(theme, SegmentType.values[index]),
            separatorBuilder: (context, index) => divider,
          ),
          dividerL,
          SliverToBoxAdapter(
            child: _userIdItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(
            child: _blockServerItem(theme, titleStyle, subTitleStyle),
          ),
          dividerL,
          SliverToBoxAdapter(child: _aboutItem(titleStyle, subTitleStyle)),
          dividerL,
          SliverToBoxAdapter(
            child: SizedBox(
              height: 55 + MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    ThemeData theme,
    SegmentType category,
  ) {
    String behaviorLabel(SkipType type) => switch (type) {
      SkipType.alwaysSkip => '自动处理',
      SkipType.skipOnce => '处理一次',
      _ => type.label,
    };
    return Builder(
      builder: (context) {
        final color = _settings.colors[category.index];
        final behavior = _settings.behaviors[category]!;
        final isDisable = behavior == SkipType.disable;
        return ListTile(
          dense: true,
          enabled: !isDisable,
          onTap: () => onSelectColor(context, category, color),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        height: 10,
                        width: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14, height: 1),
                    ),
                    TextSpan(
                      text: ' ${category.title}',
                      style: const TextStyle(fontSize: 14, height: 1),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (btnContext) {
                  return PopupMenuButton<SkipType>(
                    initialValue: behavior,
                    onSelected: (value) =>
                        _save(_actions.saveBehavior(category, value)),
                    itemBuilder: (context) => SkipType.values
                        .map(
                          (type) => AppPopupMenuItem<SkipType>(
                            value: type,
                            child: Text(behaviorLabel(type)),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text.rich(
                        style: TextStyle(
                          height: 1,
                          fontSize: 14,
                          color: isDisable
                              ? theme.colorScheme.outline.withValues(
                                  alpha: 0.7,
                                )
                              : theme.colorScheme.secondary,
                        ),
                        strutStyle: const StrutStyle(
                          height: 1,
                          leading: 0,
                          fontSize: 14,
                        ),
                        TextSpan(
                          children: [
                            TextSpan(text: behaviorLabel(behavior)),
                            WidgetSpan(
                              alignment: .middle,
                              child: Icon(
                                size: 14,
                                MdiIcons.unfoldMoreHorizontal,
                                color: isDisable
                                    ? theme.colorScheme.outline.withValues(
                                        alpha: 0.7,
                                      )
                                    : theme.colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          subtitle: Text(
            category.description,
            style: TextStyle(
              fontSize: 12,
              color: isDisable ? null : theme.colorScheme.outline,
            ),
          ),
        );
      },
    );
  }
}
