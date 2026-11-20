import 'package:pili_aurora_next/common/widgets/flutter/refresh_indicator.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/community/domain/dyn_topic_top/topic_item.dart';
import 'package:pili_aurora_next/pages/dynamics_select_topic/widgets/item.dart';
import 'package:pili_aurora_next/features/community/application/topic_queries.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/route_manager.dart';
import 'package:material_ui/material_ui.dart';

class DynTopicRcmdPage extends ConsumerStatefulWidget {
  const DynTopicRcmdPage({super.key});

  @override
  ConsumerState<DynTopicRcmdPage> createState() => _DynTopicRcmdPageState();
}

class _DynTopicRcmdPageState extends ConsumerState<DynTopicRcmdPage> {
  final _owner = Object();
  RecommendedTopics get _actions =>
      ref.read(recommendedTopicsProvider(_owner).notifier);

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(title: const Text('话题')),
      body: refreshIndicator(
        onRefresh: _actions.onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ViewSliverSafeArea(
              sliver: _buildBody(
                ref.watch(recommendedTopicsProvider(_owner)).loading,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<TopicItem>?> loadingState) {
    return switch (loadingState) {
      Loading() => linearLoading,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length,
                itemBuilder: (context, index) {
                  return DynTopicItem(
                    item: response[index],
                    onTap: (item) => Get.toNamed(
                      '/dynTopic',
                      parameters: {
                        'id': item.id.toString(),
                        'name': item.name,
                      },
                    ),
                  );
                },
              )
            : HttpError(onReload: _actions.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _actions.onReload,
      ),
    };
  }
}
