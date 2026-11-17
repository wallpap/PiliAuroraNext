import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/http/loading_state.dart';

class DiscoveryFooter extends StatelessWidget {
  const DiscoveryFooter({super.key, required this.error, required this.retry});
  final Error? error;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: error == null
        ? const SizedBox.shrink()
        : Center(
            child: TextButton(
              onPressed: retry,
              child: Text('${error.toString()} · 重试'),
            ),
          ),
  );
}
