import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/common/widgets/dialog/simple_dialog_option.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/pages/whisper_block/view.dart';
import 'package:pili_aurora_next/pages/whisper_settings/widgets/item.dart';
import 'package:pili_aurora_next/services/messaging/settings.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';
import 'package:pili_aurora_next/services/messaging/settings_providers.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class WhisperSettingsPage extends ConsumerStatefulWidget {
  const WhisperSettingsPage({
    super.key,
    this.section = WhisperSettingsSection.all,
    this.onUpdate,
  });

  final WhisperSettingsSection section;
  final ValueChanged<WhisperSettingConfirmation>? onUpdate;

  @override
  ConsumerState<WhisperSettingsPage> createState() =>
      _WhisperSettingsPageState();
}

class _WhisperSettingsPageState extends ConsumerState<WhisperSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = whisperSettingsProvider(widget.section);
    final settings = ref.watch(provider);
    final handle = ref.read(provider.notifier).handle;
    return SimpleScaffold(
      appBar: AppBar(title: Text(settings.title)),
      body: _buildBody(theme, settings.loadingState, handle),
    );
  }

  Future<void> onSet(
    int key,
    WhisperSettingEdit edit,
    WhisperSettingsHandle handle,
  ) async {
    if (!mounted || !handle.isActive) return;
    final result = await handle.edit(key, edit);
    if (!mounted || !handle.isActive) return;
    if (result case Success(:final response)) {
      widget.onUpdate?.call(response);
    } else {
      result.toast();
    }
  }

  void onRedirect(
    ThemeData theme,
    int key,
    WhisperSettingsDestination destination,
    WhisperSettingsHandle handle,
  ) {
    if (!handle.isActive) return;
    switch (destination) {
      case WhisperSettingsSubpage(:final section):
        Get.to(
          WhisperSettingsPage(
            section: section,
            onUpdate: (child) {
              if (mounted) handle.mergeChild(key, child);
            },
          ),
          preventDuplicates: false,
        );
      case WhisperSettingsWindow(:final options):
        showDialog(
          context: context,
          builder: (context) => SimpleDialog(
            clipBehavior: Clip.hardEdge,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              for (final (index, option) in options.indexed)
                DialogOption(
                  onPressed: () {
                    if (option.selected) return;
                    Navigator.of(context).pop();
                    onSet(
                      key,
                      SelectWhisperOption(index, option.label),
                      handle,
                    );
                  },
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: option.selected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      case WhisperSettingsShortcut.blacklist:
        Get.toNamed('/blackListPage');
      case WhisperSettingsShortcut.blockedKeywords:
        Get.to(const WhisperBlockPage());
      case WhisperSettingsLink(:final url):
        if (url.startsWith('http')) {
          Get.toNamed('/webview', parameters: {'url': url});
        } else {
          SmartDialog.showToast(url);
        }
    }
  }

  Widget _buildBody(
    ThemeData theme,
    LoadingState<Map<int, WhisperSetting>> loadingState,
    WhisperSettingsHandle handle,
  ) {
    switch (loadingState) {
      case Loading():
        return const SizedBox.shrink();
      case Success(:final response):
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
                  onEdit: (edit) => onSet(key, edit, handle),
                  onRedirect: (destination) =>
                      onRedirect(theme, key, destination, handle),
                );
              },
              separatorBuilder: (context, index) => divider,
            );
          },
        );
      case Error(:final errMsg):
        return scrollErrorWidget(
          errMsg: errMsg,
          onReload: handle.refresh,
        );
    }
  }
}
