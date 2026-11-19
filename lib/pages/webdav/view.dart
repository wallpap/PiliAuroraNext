import 'package:pili_aurora_next/common/style.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/view_insets_safe_area.dart';
import 'package:pili_aurora_next/pages/webdav/webdav.dart';
import 'package:pili_aurora_next/services/settings/webdav_preferences.dart';
import 'package:pili_aurora_next/services/diagnostics/redact.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class WebDavSettingPage extends StatefulWidget {
  const WebDavSettingPage({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<WebDavSettingPage> createState() => _WebDavSettingPageState();
}

class _WebDavSettingPageState extends State<WebDavSettingPage> {
  final _initial = WebDavPreferences.read();
  late final _uriCtr = TextEditingController(text: _initial.uri);
  late final _usernameCtr = TextEditingController(text: _initial.username);
  late final _passwordCtr = TextEditingController(text: _initial.password);
  late final _directoryCtr = TextEditingController(text: _initial.directory);
  bool _obscureText = true;

  @override
  void dispose() {
    _uriCtr.dispose();
    _usernameCtr.dispose();
    _passwordCtr.dispose();
    _directoryCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: showAppBar ? AppBar(title: const Text('WebDAV 设置')) : null,
      body: ViewInsetsSafeArea(
        child: ListView(
          padding: padding.copyWith(
            top: 20,
            left: 20 + (showAppBar ? padding.left : 0),
            right: 20 + (showAppBar ? padding.right : 0),
            bottom: padding.bottom + 100,
          ),
          children: [
            TextField(
              controller: _uriCtr,
              decoration: const InputDecoration(
                labelText: '地址',
                helperText: '使用 HTTPS；本机 HTTP 每次操作需确认',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameCtr,
              decoration: const InputDecoration(
                labelText: '用户',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordCtr,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                  icon: _obscureText
                      ? const Icon(Icons.visibility)
                      : const Icon(Icons.visibility_off),
                ),
              ),
              obscureText: _obscureText,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _directoryCtr,
              decoration: const InputDecoration(
                labelText: '路径',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: Style.mdRadius,
                      ),
                    ),
                    onPressed: (const WebDav()).backup,
                    child: const Text('备份设置'),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: Style.mdRadius,
                      ),
                    ),
                    onPressed: (const WebDav()).restore,
                    child: const Text('恢复设置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      fab: Padding(
        padding: .only(
          right: kFloatingActionButtonMargin + (showAppBar ? padding.right : 0),
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: ViewInsetsSafeArea(
          child: FloatingActionButton(
            child: const Icon(Icons.save),
            onPressed: () async {
              final draft = (
                uri: _uriCtr.text.trim(),
                username: _usernameCtr.text,
                password: _passwordCtr.text,
                directory: _directoryCtr.text,
              );
              try {
                await WebDavPreferences.save(draft);
                if (!mounted || draft.uri.isEmpty) return;
                final res = await (const WebDav()).init();
                if (mounted) {
                  SmartDialog.showToast(
                    res.first ? '配置成功' : '配置失败: ${res.second}',
                  );
                }
              } catch (error) {
                if (!mounted) return;
                SmartDialog.showToast(
                  '配置失败: ${DiagnosticRedactor.text(error)}',
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
