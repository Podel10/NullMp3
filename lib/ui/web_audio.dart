import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/artwork.dart';
import '../data/network.dart';
import '../data/web_audio.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/settings.dart';
import 'widgets.dart';

class WebAudioScreen extends StatefulWidget {
  const WebAudioScreen({super.key});

  @override
  State<WebAudioScreen> createState() => _WebAudioScreenState();
}

class _WebAudioScreenState extends State<WebAudioScreen> {
  final _link = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _cancel = false;
  String? _error;
  WebAudioProgress? _progress;
  final List<WebAudioFile> _done = [];

  @override
  void initState() {
    super.initState();
    unawaited(_pasteClipboard(onlyIfEmpty: true));
  }

  @override
  void dispose() {
    _cancel = true;
    _link.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard({bool onlyIfEmpty = false}) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;
      if (onlyIfEmpty && _link.text.trim().isNotEmpty) return;
      if (onlyIfEmpty && parseWebAudioUrl(text) == null) return;
      if (!mounted) return;
      setState(() {
        _link.text = text;
        _link.selection = TextSelection.collapsed(offset: text.length);
        _error = null;
      });
    } catch (_) {}
  }

  Future<void> _download() async {
    final s = context.s;
    final raw = _link.text.trim();
    if (raw.isEmpty || parseWebAudioUrl(raw) == null) {
      setState(() => _error = s.downloadAudioBadLink);
      return;
    }
    if (NetworkGate.offline) {
      setState(() => _error = s.downloadAudioOffline);
      return;
    }

    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    await settings.requestMediaPermission();

    setState(() {
      _busy = true;
      _cancel = false;
      _error = null;
      _progress = null;
      _done.clear();
    });

    try {
      final files = await downloadWebAudio(
        raw,
        isCancelled: () => _cancel || !mounted,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      final dir = files.isEmpty ? null : p.dirname(files.first.path);
      if (dir != null) await settings.addFolderPath(dir);
      await settings.rememberFiles([for (final file in files) file.path]);
      await library.addFiles([for (final file in files) file.path]);
      for (final file in files) {
        if (file.cover != null) {
          await ArtworkStore.instance.put(file.path, file.cover!);
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done
          ..clear()
          ..addAll(files);
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.downloadAudioSaved(files.length))),
      );
    } on WebAudioException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = switch (error.code) {
          'offline' => s.downloadAudioOffline,
          'badUrl' => s.downloadAudioBadLink,
          'cancelled' => s.downloadAudioCancelled,
          _ => s.downloadAudioFailed,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = s.downloadAudioFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: Text(s.downloadAudio)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(s.downloadAudioHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _link,
            focusNode: _focus,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onSubmitted: _busy ? null : (_) => unawaited(_download()),
            decoration: InputDecoration(
              labelText: s.downloadAudioLink,
              hintText: 'https://soundcloud.com/…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: s.downloadAudioPaste,
                onPressed: _busy ? null : () => _pasteClipboard(),
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _download,
            icon: const Icon(Icons.download_rounded),
            label: Text(_busy ? s.downloadAudioBusy : s.downloadAudioGo),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _cancel = true),
              child: Text(s.cancel),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress?.fraction),
            if (progress != null) ...[
              const SizedBox(height: 8),
              Text(
                progress.stage == 'tag'
                    ? s.downloadAudioTagging
                    : s.downloadAudioItem(progress.index, progress.total, progress.title),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          if (_done.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              p.dirname(_done.first.path),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 8),
            for (final file in _done)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CoverArt(
                  track: Track(
                    path: file.path,
                    title: file.title,
                    artist: file.artist,
                    album: '',
                    genre: '',
                    durationMs: 0,
                    modifiedMs: 0,
                  ),
                  size: 48,
                ),
                title: Text(file.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(file.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        ],
      ),
    );
  }
}
