import 'package:flutter/material.dart';

import '../data/video_gif.dart';
import '../l10n/strings.dart';
import 'video_gif.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.tools)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (videoGifSupported)
            ListTile(
              leading: const Icon(Icons.gif_box_outlined),
              title: Text(s.videoToGif),
              subtitle: Text(s.videoToGifHint),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoToGifScreen()),
              ),
            ),
        ],
      ),
    );
  }
}
