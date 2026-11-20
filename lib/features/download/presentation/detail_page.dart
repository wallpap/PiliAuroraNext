import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/download/presentation/library_page.dart';

class DownloadDetailPage extends StatelessWidget {
  const DownloadDetailPage({
    super.key,
    required this.pageId,
    required this.title,
    required this.progress,
  });
  final String pageId;
  final String title;
  final ChangeNotifier progress;
  @override
  Widget build(BuildContext context) => DownloadLibraryPage(
    mode: DownloadViewMode.detail,
    pageId: pageId,
    title: title,
    progress: progress,
  );
}
