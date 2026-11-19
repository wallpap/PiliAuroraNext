import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart';
import 'package:pili_aurora_next/grpc/im.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

typedef WhisperSettingsPageData = ({
  String title,
  Map<int, WhisperSettingRecord> records,
});

abstract final class WhisperSettingsAdapter {
  static Future<LoadingState<WhisperSettingsPageData>> load(
    MessagingSession session,
    WhisperSettingsSection section,
  ) async {
    final type = IMSettingType.valueOf(section.code);
    if (type == null) return const Error('不支持的设置页面');
    final result = await session.run(
      (account) => ImGrpc.getImSettings(account: account, type: type),
    );
    return switch (result) {
      Success(:final response) => Success((
        title: response.pageTitle,
        records: {
          for (final entry in response.settings.entries)
            entry.key: WhisperSettingRecord._(entry.value),
        },
      )),
      Error() => result,
      Loading() => LoadingState.loading(),
    };
  }

  static Future<LoadingState<void>> save(
    MessagingSession session,
    int key,
    WhisperSettingRecord record,
  ) => session.run<void>(
    (account) =>
        ImGrpc.setImSettings(account: account, settings: {key: record._wire}),
  );
}

final class WhisperSettingRecord {
  WhisperSettingRecord._(this._wire) {
    _wire.freeze();
  }

  final Setting _wire;
  late final WhisperSetting value = _project(_wire);

  WhisperSettingRecord? edit(WhisperSettingEdit edit) {
    final next = _wire.deepCopy();
    if (edit case SetWhisperToggle(:final enabled) when next.hasSwitch_1()) {
      next.switch_1.switchOn = enabled;
    } else if (edit case SelectWhisperOption(:final index, :final label)) {
      final window = next.redirect.hasWindowSelect();
      if (!window && !next.hasSelect()) return null;
      final items = window ? next.redirect.windowSelect.item : next.select.item;
      if (index < 0 || index >= items.length || items[index].text != label) {
        return null;
      }
      for (final (position, option) in items.indexed) {
        option.selected = position == index;
      }
      if (window) next.redirect.selectedSummary = label;
    } else {
      return null;
    }
    return WhisperSettingRecord._(next);
  }

  WhisperSettingRecord? withChild(int key, WhisperSettingRecord child) {
    if (!_wire.redirect.hasSettingPage()) return null;
    final next = _wire.deepCopy();
    next.redirect.settingPage.subSettings[key] = child._wire.deepCopy();
    return WhisperSettingRecord._(next);
  }

  static WhisperSetting _project(Setting setting) {
    if (setting.hasSwitch_1()) {
      final toggle = setting.switch_1;
      return WhisperSettingToggle(
        toggle.title,
        toggle.hasSubtitle() ? toggle.subtitle : null,
        toggle.switchOn,
      );
    }
    if (setting.hasSelect()) {
      return WhisperSettingChoices(_options(setting.select.item));
    }
    if (!setting.hasRedirect()) return const WhisperSettingUnsupported();
    final redirect = setting.redirect;
    final subpage = redirect.settingPage;
    final destination = switch (redirect.whichContent()) {
      .settingPage when subpage.hasParentSettingType() =>
        WhisperSettingsSubpage(
          WhisperSettingsSection(subpage.parentSettingType.value),
        ),
      .windowSelect => WhisperSettingsWindow(
        _options(redirect.windowSelect.item),
      ),
      .otherPage when redirect.otherPage.hasUrl() =>
        redirect.title == '黑名单'
            ? WhisperSettingsShortcut.blacklist
            : WhisperSettingsLink(redirect.otherPage.url),
      .settingPage when subpage.hasUrl() =>
        redirect.title == '消息屏蔽词'
            ? WhisperSettingsShortcut.blockedKeywords
            : WhisperSettingsLink(subpage.url),
      _ => null,
    };
    return WhisperSettingRedirect(
      redirect.title,
      redirect.hasSubtitle() ? redirect.subtitle : null,
      _summary(redirect),
      destination,
    );
  }

  static String? _summary(SettingRedirect redirect) {
    String? selected;
    for (final child in redirect.settingPage.subSettings.values) {
      if (child.hasSelect()) {
        final option = child.select.item
            .where((option) => option.selected)
            .firstOrNull;
        if (option != null) selected = option.text;
      } else if (child.switch_1.switchOn) {
        return selected ?? child.switch_1.title;
      }
    }
    return selected ??
        (redirect.hasSelectedSummary() ? redirect.selectedSummary : null);
  }

  static List<WhisperSettingOption> _options(List<SelectItem> options) =>
      List.unmodifiable([
        for (final option in options)
          (label: option.text, selected: option.selected),
      ]);
}
