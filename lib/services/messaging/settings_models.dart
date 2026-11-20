typedef BlockedKeywords = ({
  List<String> words,
  int listLimit,
  int charLimit,
});

extension type const WhisperSettingsSection(int code) {
  static const all = WhisperSettingsSection(0);
  static const replies = WhisperSettingsSection(17);
  static const mentions = WhisperSettingsSection(18);
  static const likes = WhisperSettingsSection(19);
}

typedef WhisperSettingOption = ({String label, bool selected});

sealed class WhisperSetting {
  const WhisperSetting();
}

final class WhisperSettingUnsupported extends WhisperSetting {
  const WhisperSettingUnsupported();
}

final class WhisperSettingToggle extends WhisperSetting {
  const WhisperSettingToggle(this.title, this.subtitle, this.enabled);

  final String title;
  final String? subtitle;
  final bool enabled;
}

final class WhisperSettingChoices extends WhisperSetting {
  const WhisperSettingChoices(this.options);

  final List<WhisperSettingOption> options;
}

final class WhisperSettingRedirect extends WhisperSetting {
  const WhisperSettingRedirect(
    this.title,
    this.subtitle,
    this.summary,
    this.destination,
  );

  final String title;
  final String? subtitle, summary;
  final WhisperSettingsDestination? destination;
}

sealed class WhisperSettingsDestination {
  const WhisperSettingsDestination();
}

final class WhisperSettingsSubpage extends WhisperSettingsDestination {
  const WhisperSettingsSubpage(this.section);

  final WhisperSettingsSection section;
}

final class WhisperSettingsWindow extends WhisperSettingsDestination {
  const WhisperSettingsWindow(this.options);

  final List<WhisperSettingOption> options;
}

final class WhisperSettingsLink extends WhisperSettingsDestination {
  const WhisperSettingsLink(this.url);

  final String url;
}

enum WhisperSettingsShortcut implements WhisperSettingsDestination {
  blacklist,
  blockedKeywords,
}

sealed class WhisperSettingEdit {
  const WhisperSettingEdit();
}

final class SetWhisperToggle extends WhisperSettingEdit {
  const SetWhisperToggle(this.enabled);

  final bool enabled;
}

final class SelectWhisperOption extends WhisperSettingEdit {
  const SelectWhisperOption(this.index, this.label);

  final int index;
  final String label;
}
