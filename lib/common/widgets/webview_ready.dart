import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/services/webview_environment.dart';

/// 原生网页创建前的共享环境屏障；离页后不再挂载迟到的网页。
class WebViewReady extends StatefulWidget {
  const WebViewReady({super.key, required this.builder, this.prepare});

  final WidgetBuilder builder;
  final Future<void> Function()? prepare;

  @override
  State<WebViewReady> createState() => _WebViewReadyState();
}

class _WebViewReadyState extends State<WebViewReady> {
  void Function()? _release;
  late Future<void> _ready = _prepare();

  @override
  void initState() {
    super.initState();
    if (AppWebViewEnvironment.closing.value) return;
    _release = AppWebViewEnvironment.retain();
    AppWebViewEnvironment.closing.addListener(_onEnvironmentClosing);
  }

  void _onEnvironmentClosing() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _releasePage());
  }

  void _releasePage() {
    final release = _release;
    _release = null;
    release?.call();
  }

  @override
  void dispose() {
    AppWebViewEnvironment.closing.removeListener(_onEnvironmentClosing);
    _releasePage();
    super.dispose();
  }

  Future<void> _prepare() async {
    await AppWebViewEnvironment.ensureInitialized();
    if (mounted && !AppWebViewEnvironment.closing.value) {
      await widget.prepare?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppWebViewEnvironment.closing.value) return const SizedBox.shrink();
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                _ready = _prepare();
              }),
              child: const Text('网页初始化失败，点击重试'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context);
      },
    );
  }
}
