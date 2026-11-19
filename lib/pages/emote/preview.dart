import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/common/widgets/image/network_img_layer.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/features/community/application/emote_management.dart';
import 'package:pili_aurora_next/http/loading_state.dart' show Error;
import 'package:pili_aurora_next/models/common/image_type.dart';
import 'package:pili_aurora_next/features/community/domain/emote/emote.dart';
import 'package:pili_aurora_next/features/community/domain/emote/package.dart';

class EmotePackagePreviewPage extends ConsumerWidget {
  const EmotePackagePreviewPage({super.key, required this.package});

  final Package package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = emotePackagePreviewProvider(package.id);
    final snapshot = ref.watch(provider);
    return SimpleScaffold(
      appBar: AppBar(title: Text(package.text ?? '表情包预览')),
      body: SafeArea(
        top: false,
        child: snapshot.when(
          skipLoadingOnRefresh: false,
          loading: () => m3eLoading,
          error: (error, _) => Center(
            child: TextButton.icon(
              onPressed: () => ref.invalidate(provider),
              icon: const Icon(Icons.refresh),
              label: Text(
                '${error is Error ? error.errMsg ?? '加载失败' : '加载失败'}，点击重试',
              ),
            ),
          ),
          data: _buildEmotes,
        ),
      ),
    );
  }

  Widget _buildEmotes(Package package) {
    final emotes = package.emote ?? const <Emote>[];
    if (emotes.isEmpty) return const Center(child: Text('暂无可预览的表情'));
    final isTextEmote = package.type == 4;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 112,
        mainAxisExtent: 110,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: emotes.length,
      itemBuilder: (context, index) {
        final emote = emotes[index];
        return InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(emote.text ?? '表情预览'),
              content: isTextEmote
                  ? Text(emote.text ?? '', style: const TextStyle(fontSize: 32))
                  : NetworkImgLayer(
                      src: emote.url,
                      width: 160,
                      height: 160,
                      type: ImageType.emote,
                      fit: BoxFit.contain,
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isTextEmote) ...[
                  NetworkImgLayer(
                    src: emote.url,
                    width: 48,
                    height: 48,
                    type: ImageType.emote,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  emote.text ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
