import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart'
    show IMSettingType, Setting;
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/whisper_block/view.dart';
import 'package:pili_aurora_next/pages/whisper_settings/widgets/item.dart';
import 'package:pili_aurora_next/services/messaging/providers.dart';
import 'package:pili_aurora_next/services/messaging/settings_providers.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:protobuf/protobuf.dart'
    show GeneratedMessageGenericExtensions, PbMap;

class WhisperSettingsPage extends ConsumerStatefulWidget {
  const WhisperSettingsPage({
    super.key,
    required this.imSettingType,
    this.onUpdate,
  });

  final IMSettingType imSettingType;
  final ValueChanged<Map<int, Setting>>? onUpdate;

  @override
  ConsumerState<WhisperSettingsPage> createState() =>
      _WhisperSettingsPageState();
}

class _WhisperSettingsPageState extends ConsumerState<WhisperSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(whisperSettingsProvider(widget.imSettingType));
    final controller = ref.read(
      whisperSettingsProvider(widget.imSettingType).notifier,
    );
    final session = ref.read(messagingSessionProvider);
    return SimpleScaffold(
      appBar: AppBar(title: Text(settings.title)),
      body: _buildBody(
        theme,
        settings.loadingState,
        controller,
        () => mounted && session.isActive,
      ),
    );
  }

  Future<void> onSet(
    int key,
    Setting item,
    WhisperSettingsNotifier controller,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    final result = await controller.setSetting(key, item);
    if (!isCurrent()) return;
    if (result.isSuccess) {
      widget.onUpdate?.call({key: item.deepCopy()});
    } else {
      result.toast();
    }
  }

  void onRedirect(
    ThemeData theme,
    int key,
    Setting item,
    WhisperSettingsNotifier controller,
    bool Function() isCurrent,
  ) {
    if (!isCurrent()) return;
    if (item.redirect.settingPage.hasParentSettingType()) {
      Get.to(
        WhisperSettingsPage(
          imSettingType: item.redirect.settingPage.parentSettingType,
          onUpdate: (value) {
            if (isCurrent()) controller.mergeSubSettings(key, value);
          },
        ),
        preventDuplicates: false,
      );
    } else if (item.redirect.hasWindowSelect()) {
      showDialog(
        context: context,
        builder: (context) => SimpleDialog(
          clipBehavior: Clip.hardEdge,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          children: item.redirect.windowSelect.item.map(
            (option) {
              return DialogOption(
                onPressed: () async {
                  if (option.selected) return;
                  Get.back();
                  final updated = item.deepCopy();
                  for (final candidate in updated.redirect.windowSelect.item) {
                    candidate.selected = candidate.text == option.text;
                  }
                  updated.redirect.selectedSummary = option.text;
                  await onSet(key, updated, controller, isCurrent);
                },
                child: Text(
                  option.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: option.selected ? theme.colorScheme.primary : null,
                  ),
                ),
              );
            },
          ).toList(),
        ),
      );
    } else if (item.redirect.otherPage.hasUrl()) {
      if (item.redirect.title == '黑名单') {
        Get.toNamed('/blackListPage');
      } else if (item.redirect.otherPage.url.startsWith('http')) {
        Get.toNamed(
          '/webview',
          parameters: {'url': item.redirect.otherPage.url},
        );
      } else {
        SmartDialog.showToast(item.redirect.otherPage.url);
      }
    } else if (item.redirect.settingPage.hasUrl()) {
      if (item.redirect.title == '消息屏蔽词') {
        Get.to(const WhisperBlockPage());
      } else if (item.redirect.settingPage.url.startsWith('http')) {
        Get.toNamed(
          '/webview',
          parameters: {'url': item.redirect.settingPage.url},
        );
      } else {
        SmartDialog.showToast(item.redirect.settingPage.url);
      }
    }
  }

  Widget _buildBody(
    ThemeData theme,
    LoadingState<PbMap<int, Setting>> loadingState,
    WhisperSettingsNotifier controller,
    bool Function() isCurrent,
  ) {
    switch (loadingState) {
      case Loading():
        return const SizedBox.shrink();
      case Success<PbMap<int, Setting>>(:final response):
        final divider = Divider(
          height: 1,
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        );
        return Builder(
          builder: (context) {
            final keys = response.keys.toList()..sort();
            return ListView.separated(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final key = keys[index];
                final item = response[key]!;
                return ImSettingsItem(
                  item: item,
                  onSet: (setting) =>
                      onSet(key, setting, controller, isCurrent),
                  onRedirect: () =>
                      onRedirect(theme, key, item, controller, isCurrent),
                );
              },
              separatorBuilder: (context, index) => divider,
            );
          },
        );
      case Error(:final errMsg):
        return scrollErrorWidget(
          errMsg: errMsg,
          onReload: controller.onReload,
        );
    }
  }
}
