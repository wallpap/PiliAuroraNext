import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

class LiveInfoLabel extends StatelessWidget {
  const LiveInfoLabel({super.key, required this.text});

  final ValueListenable<String?> text;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: text,
    builder: (context, label, child) => label == null
        ? const SizedBox.shrink()
        : Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
  );
}
