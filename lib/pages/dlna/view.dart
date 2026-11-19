import 'dart:async';

import 'package:pili_aurora_next/common/widgets/loading_widget/http_error.dart';
import 'package:pili_aurora_next/common/widgets/loading_widget/loading_widget.dart';
import 'package:pili_aurora_next/common/widgets/scaffold/simple_scaffold.dart';
import 'package:pili_aurora_next/common/widgets/view_sliver_safe_area.dart';
import 'package:pili_aurora_next/features/playback/application/dlna_session.dart';
import 'package:material_ui/material_ui.dart';

class DLNAPage extends StatefulWidget {
  const DLNAPage({super.key, required this.url, this.title = ''});

  final String url;
  final String title;

  @override
  State<DLNAPage> createState() => _DLNAPageState();
}

class _DLNAPageState extends State<DLNAPage> {
  final _session = DlnaSession();

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    unawaited(_session.search());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('投屏'),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: _session.searching || _session.connecting
                ? null
                : _session.search,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          if (_session.searching || _session.connecting) linearLoading,
          if (_session.searchError case final error?)
            if (_session.targets.isNotEmpty)
              SliverToBoxAdapter(child: ListTile(title: Text(error))),
          ViewSliverSafeArea(sliver: _buildBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    final targets = _session.targets;
    if (!_session.searching && targets.isEmpty) {
      final permanentlyDenied = _session.permissionPermanentlyDenied;
      return HttpError(
        errMsg: _session.searchError ?? '没有设备',
        btnText: permanentlyDenied
            ? '前往设置'
            : _session.permissionDenied
            ? '授予权限'
            : null,
        onReload: permanentlyDenied
            ? _session.openPermissionSettings
            : _session.search,
      );
    }
    if (targets.isNotEmpty) {
      return SliverList.builder(
        itemCount: targets.length,
        itemBuilder: (context, index) {
          final (:key, :name) = targets[index];
          final isCurr = key == _session.selectedKey;
          return ListTile(
            enabled: !_session.connecting,
            title: Text(
              name,
              style: isCurr ? TextStyle(color: colorScheme.primary) : null,
            ),
            subtitle: Text(key),
            onTap: () async {
              if (isCurr) return;
              final route = ModalRoute.of(context);
              bool current() => mounted && route?.isCurrent == true;
              final result = await _session.connect(
                key: key,
                url: widget.url,
                title: widget.title,
                isCurrent: current,
              );
              if (current() && !result.isSuccess) result.toast();
            },
          );
        },
      );
    }
    return const SliverToBoxAdapter();
  }
}
