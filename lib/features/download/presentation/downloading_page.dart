import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/download/presentation/library_page.dart';

class DownloadingPage extends StatelessWidget {
  const DownloadingPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const DownloadLibraryPage(mode: DownloadViewMode.queued);
}
