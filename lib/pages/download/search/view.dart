import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/download/presentation/library_page.dart';

class DownloadSearchPage extends StatelessWidget {
  const DownloadSearchPage({super.key, required this.progress});
  final ChangeNotifier progress;
  @override
  Widget build(BuildContext context) =>
      DownloadLibraryPage(mode: DownloadViewMode.search, progress: progress);
}
