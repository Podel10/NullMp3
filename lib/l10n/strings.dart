import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../theme/app_theme.dart';
import 'app_language.dart';
import 'catalog_en.dart';

export 'app_language.dart';

class L10n {
  L10n._();

  static String? _loadedCode;
  static Map<String, String> _overlay = const {};

  static Future<void> ensure(AppLanguage lang) async {
    if (lang.code == 'en') {
      _loadedCode = 'en';
      _overlay = const {};
      return;
    }
    if (_loadedCode == lang.code) return;
    try {
      final raw = await rootBundle.loadString('assets/l10n/${lang.code}.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _overlay = {
          for (final entry in decoded.entries)
            if (entry.value is String && (entry.value as String).isNotEmpty)
              entry.key.toString(): entry.value as String,
        };
      } else {
        _overlay = const {};
      }
    } catch (_) {
      _overlay = const {};
    }
    _loadedCode = lang.code;
  }

  static String get(AppLanguage lang, String key) {
    if (lang.code != 'en' && _loadedCode == lang.code) {
      final overlay = _overlay[key];
      if (overlay != null && overlay.isNotEmpty) return overlay;
    }
    return catalogEn[key] ?? key;
  }
}

extension AppL10n on BuildContext {
  S get s => S(Provider.of<SettingsController>(this, listen: false).language);
}

class S {
  const S(this.lang);
  final AppLanguage lang;

  String _(String key, [Map<String, String>? vars]) {
    var value = L10n.get(lang, key);
    if (vars != null) {
      vars.forEach((name, replacement) {
        value = value.replaceAll('{$name}', replacement);
      });
    }
    return value;
  }

  String get appName => 'Null MP3';
  String get searchLanguages => _('searchLanguages');
  String get settings => _('settings');
  String get language => _('language');
  String get chooseLanguage => _('chooseLanguage');
  String get chooseWallpaper => _('chooseWallpaper');
  String get selectSongs => _('selectSongs');
  String get appearance => _('appearance');
  String get library => _('library');
  String get about => _('about');

  String get tabRecommended => _('tabRecommended');
  String get tabSongs => _('tabSongs');
  String get tabAlbums => _('tabAlbums');
  String get tabArtists => _('tabArtists');
  String get tabPlaylists => _('tabPlaylists');
  String get tabFolders => _('tabFolders');

  String get recentlyPlayed => _('recentlyPlayed');
  String get mostPopular => _('mostPopular');
  String get favorites => _('favorites');
  String get recentlyAdded => _('recentlyAdded');
  String get mostPlayed => _('mostPlayed');
  String listens(int n) => '🎧 $n';
  String get seeAll => _('seeAll');
  String get playToFill => _('playToFill');

  String get search => _('search');
  String get searchHint => _('searchHint');
  String get searchYourLibrary => _('searchYourLibrary');
  String get noMatches => _('noMatches');

  String get equalizer => _('equalizer');
  String get sleepTimer => _('sleepTimer');
  String get themeSettings => _('themeSettings');
  String get addFolder => _('addFolder');
  String get addFiles => _('addFiles');
  String get sort => _('sort');
  String get sortTitle => _('sortTitle');
  String get sortArtist => _('sortArtist');
  String get sortAlbum => _('sortAlbum');
  String get sortDuration => _('sortDuration');
  String get sortDate => _('sortDate');

  String songsCount(int n) => _('songsCount', {'n': '$n'});
  String albumsCount(int n) => _('albumsCount', {'n': '$n'});
  String songsInLibrary(int n) => _('songsInLibrary', {'n': '$n'});
  String albumsAndSongs(int albums, int songs) =>
      _('albumsAndSongs', {'albums': '$albums', 'songs': '$songs'});
  String librarySize(int songs, int albums, int artists) => _('librarySize', {
        'songs': '$songs',
        'albums': '$albums',
        'artists': '$artists',
      });
  String tracksCount(int n) => _('tracksCount', {'n': '$n'});

  String get newPlaylist => _('newPlaylist');
  String get rename => _('rename');
  String get delete => _('delete');
  String get renamePlaylist => _('renamePlaylist');
  String get playlistRemoved => _('playlistRemoved');
  String get noSongsInPlaylist => _('noSongsInPlaylist');
  String get nothingHereYet => _('nothingHereYet');
  String get playAll => _('playAll');
  String get shuffle => _('shuffle');
  String get nameHint => _('nameHint');
  String get cancel => _('cancel');
  String get save => _('save');
  String get close => _('close');
  String get show => _('show');
  String get off => _('off');

  String get noMusicYet => _('noMusicYet');
  String get emptyLibraryHint => _('emptyLibraryHint');
  String get updateLibrary => _('updateLibrary');
  String get updatingLibrary => _('updatingLibrary');
  String get lookingForMusic => _('lookingForMusic');
  String scanStatus(String? key) => switch (key) {
        'updatingLibrary' => updatingLibrary,
        'lookingForMusic' => lookingForMusic,
        _ => key ?? '',
      };

  String get alreadyInLibrary => _('alreadyInLibrary');
  String addedSongs(int n) =>
      n == 1 ? _('addedSongsOne') : _('addedSongs', {'n': '$n'});

  String get foldersHint => _('foldersHint');
  String get skipShortTracks => _('skipShortTracks');
  String seconds(int n) => _('seconds', {'n': '$n'});
  String get librarySizeLabel => _('librarySizeLabel');
  String get statistics => _('statistics');
  String get listenTime => _('listenTime');
  String get tracksListened => _('tracksListened');
  String listenHours(int milliseconds) {
    final minutes = (milliseconds / 60000).floor();
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours <= 0) return _('listenMin', {'n': '$minutes'});
    if (rest == 0) return _('listenHoursOnly', {'n': '$hours'});
    return _('listenHoursMin', {'hours': '$hours', 'minutes': '$rest'});
  }

  String get disableStatistics => _('disableStatistics');
  String get enableStatistics => _('enableStatistics');
  String get statisticsOffHint => _('statisticsOffHint');

  String get offlineMode => _('offlineMode');
  String get offlineModeHint => _('offlineModeHint');

  String get hiddenSongs => _('hiddenSongs');
  String get nothingHidden => _('nothingHidden');
  String get hiddenHint => _('hiddenHint');
  String get aboutBlurb => _('aboutBlurb');
  String get faq => _('faq');
  String get faqMicQ => _('faqMicQ');
  String get faqMicA => _('faqMicA');
  String get faqWavesQ => _('faqWavesQ');
  String get faqWavesA => _('faqWavesA');
  String get faqRecordQ => _('faqRecordQ');
  String get faqRecordA => _('faqRecordA');

  String get tools => _('tools');
  String get videoToGif => _('videoToGif');
  String get videoToGifHint => _('videoToGifHint');
  String get gifReading => _('gifReading');
  String get gifBuilding => _('gifBuilding');
  String get chooseVideo => _('chooseVideo');
  String get noVideoChosen => _('noVideoChosen');
  String get gifStart => _('gifStart');
  String get gifLength => _('gifLength');
  String get gifFps => _('gifFps');
  String get gifWidth => _('gifWidth');
  String get gifAuto => _('gifAuto');
  String get convert => _('convert');
  String get converting => _('converting');
  String get preview => _('preview');
  String get previewHint => _('previewHint');
  String get previewFailed => _('previewFailed');
  String gifSaved(String size) => _('gifSaved', {'size': size});
  String get gifFailed => _('gifFailed');
  String get videoUnreadable => _('videoUnreadable');
  String gifFrames(int count) => _('gifFrames', {'count': '$count'});

  String get downloadAudio => _('downloadAudio');
  String get downloadAudioHint => _('downloadAudioHint');
  String get downloadAudioLink => _('downloadAudioLink');
  String get downloadAudioPaste => _('downloadAudioPaste');
  String get downloadAudioGo => _('downloadAudioGo');
  String get downloadAudioBusy => _('downloadAudioBusy');
  String get downloadAudioTagging => _('downloadAudioTagging');
  String get downloadAudioOffline => _('downloadAudioOffline');
  String get downloadAudioBadLink => _('downloadAudioBadLink');
  String get downloadAudioFailed => _('downloadAudioFailed');
  String get downloadAudioCancelled => _('downloadAudioCancelled');
  String downloadAudioSaved(int n) => _('downloadAudioSaved', {'n': '$n'});
  String downloadAudioItem(int index, int total, String title) => _(
        'downloadAudioItem',
        {'index': '$index', 'total': '$total', 'title': title},
      );
  String get downloadAudioFolder => _('downloadAudioFolder');

  String get libraryFolders => _('libraryFolders');
  String get libraryFoldersHint => _('libraryFoldersHint');
  String get inLibrary => _('inLibrary');
  String get nothingSelected => _('nothingSelected');
  String get tapFolderBelow => _('tapFolderBelow');
  String get foldersWithMostTracks => _('foldersWithMostTracks');
  String get noFoldersFound => _('noFoldersFound');
  String get allFoldersAdded => _('allFoldersAdded');
  String get pickFolderYourself => _('pickFolderYourself');
  String addedFolder(String name) => _('addedFolder', {'name': name});
  String removedFolder(String name) => _('removedFolder', {'name': name});
  String tracksInPath(int count, String path) =>
      _('tracksInPath', {'count': '$count', 'path': path});

  String get nothingPlaying => _('nothingPlaying');
  String get playingFrom => _('playingFrom');
  String get repeatTrack => _('repeatTrack');
  String get previousTrack => _('previousTrack');
  String get nextTrack => _('nextTrack');
  String get pause => _('pause');
  String get play => _('play');
  String get shuffleOn => _('shuffleOn');
  String get shuffleOff => _('shuffleOff');

  String get lyrics => _('lyrics');
  String get lyricsNotFound => _('lyricsNotFound');
  String get lyricsNotFoundHint => _('lyricsNotFoundHint');
  String get lyricsSearchOnline => _('lyricsSearchOnline');
  String get lyricsWrite => _('lyricsWrite');
  String get lyricsHint => _('lyricsHint');
  String get lyricsSearching => _('lyricsSearching');
  String get lyricsSearchFailed => _('lyricsSearchFailed');
  String get lyricsSearchHint => _('lyricsSearchHint');
  String get lyricsFilterDuration => _('lyricsFilterDuration');
  String get lyricsFilterArtist => _('lyricsFilterArtist');
  String get lyricsFilterSynced => _('lyricsFilterSynced');
  String get lyricsPickResult => _('lyricsPickResult');
  String lyricsHitMeta(String artist, String duration, String source) =>
      '$artist • $duration • $source';
  String get lyricsOffline => _('lyricsOffline');
  String get lyricsOfflineHint => _('lyricsOfflineHint');
  String get editLyrics => _('editLyrics');
  String get clearLyrics => _('clearLyrics');
  String get instrumental => _('instrumental');
  String get autoStyle => _('autoStyle');
  String get coverSearchHint => _('coverSearchHint');
  String get coverSearchSources => _('coverSearchSources');
  String get searchImage => _('searchImage');
  String get searchGif => _('searchGif');
  String get imageSearchHint => _('imageSearchHint');
  String get imageSearchSources => _('imageSearchSources');
  String get gifSearchHint => _('gifSearchHint');
  String get gifSearchSources => _('gifSearchSources');
  String get coverSearchFailed => _('coverSearchFailed');
  String get coverSearchApplyFailed => _('coverSearchApplyFailed');
  String get cropCover => _('cropCover');
  String get cropCoverHint => _('cropCoverHint');
  String get coverApplied => _('coverApplied');
  String get addToPlaylist => _('addToPlaylist');
  String get addToPlaylistEllipsis => _('addToPlaylistEllipsis');
  String get tagEditor => _('tagEditor');
  String get displaySettings => _('displaySettings');
  String get coverShape => _('coverShape');
  String get shapeSquare => _('shapeSquare');
  String get shapeCircle => _('shapeCircle');
  String get beatHalo => _('beatHalo');
  String get beatHaloHint => _('beatHaloHint');
  String get simpleWaves => _('simpleWaves');
  String get advancedWaves => _('advancedWaves');
  String get beatHaloModeHint => _('beatHaloModeHint');
  String get details => _('details');
  String get playbackSpeed => _('playbackSpeed');
  String get musicEditor => _('musicEditor');
  String get ringtoneEditor => musicEditor;
  String selectionMeta(double seconds, String format, int sampleRate, int bitrate) {
    return _(
      'selectionMeta',
      {
        'seconds': seconds.toStringAsFixed(2),
        'format': format,
        'sampleRate': '$sampleRate',
        'bitrate': '$bitrate',
      },
    );
  }

  String cutSaved(String title) => _('cutSaved', {'title': title});
  String get cutFailed => _('cutFailed');
  String get drivingMode => _('drivingMode');
  String get lockScreen => _('lockScreen');
  String get lockedHint => _('lockedHint');
  String get lockNow => _('lockNow');
  String get hide => _('hide');
  String get deleteFromDevice => _('deleteFromDevice');
  String get share => _('share');
  String get preparingShare => _('preparingShare');
  String get removeFromPlaylist => _('removeFromPlaylist');
  String get playPauseFade => _('playPauseFade');
  String get milliseconds300 => _('milliseconds300');
  String get crossfade => _('crossfade');

  String get hideTrack => _('hideTrack');
  String hideTrackBody(String title) => _('hideTrackBody', {'title': title});
  String get hiddenFromLibrary => _('hiddenFromLibrary');
  String deleteFileBody(String title) => _('deleteFileBody', {'title': title});
  String get fileDeleted => _('fileDeleted');
  String deleteFailed(String error) => _('deleteFailed', {'error': error});
  String shareFailed(String error) => _('shareFailed', {'error': error});
  String get deleteCancelled => _('deleteCancelled');
  String get deleteNeedPermission => _('deleteNeedPermission');
  String deleteResult(String? error) {
    if (error == null || error.isEmpty) return fileDeleted;
    if (error == 'cancelled' || error == 'needPermission') return fileActionError(error);
    return deleteFailed(error);
  }

  String fileActionError(String? code) {
    if (code == null || code.isEmpty) return '';
    if (code == 'cancelled') return deleteCancelled;
    if (code == 'needPermission') return deleteNeedPermission;
    return code;
  }

  String get cover => _('cover');
  String get changeCover => _('changeCover');
  String get changeCoverHint => _('changeCoverHint');
  String get pickCoverFailed => _('pickCoverFailed');
  String saveTagsFailed(String error) => _('saveTagsFailed', {'error': error});
  String get tagsSaved => _('tagsSaved');
  String get tagsSavedRenamed => _('tagsSavedRenamed');
  String get fieldTitle => _('fieldTitle');
  String get fieldAlbum => _('fieldAlbum');
  String get fieldArtist => _('fieldArtist');
  String get fieldAlbumArtist => _('fieldAlbumArtist');
  String get fieldComposer => _('fieldComposer');
  String get trackDetails => _('trackDetails');
  String get fieldGenre => _('fieldGenre');
  String get fieldYear => _('fieldYear');
  String get fieldDuration => _('fieldDuration');
  String get fieldPath => _('fieldPath');

  String get enableEqualizer => _('enableEqualizer');
  String get equalizerHint => _('equalizerHint');
  String get eqCustom => _('eqCustom');
  String eqPreset(String name) => switch (name) {
        'Normal' => _('eqNormal'),
        'Pop' => _('eqPop'),
        'Rock' => _('eqRock'),
        'Jazz' => _('eqJazz'),
        'Classical' => _('eqClassical'),
        'Dance' => _('eqDance'),
        'Bass boost' => _('eqBass'),
        'Treble boost' => _('eqTreble'),
        'Vocal' => _('eqVocal'),
        'Flat' => _('eqFlat'),
        'Custom' => eqCustom,
        _ => name,
      };

  String playbackSpeedValue(String value) => _('playbackSpeedValue', {'value': value});
  String playbackPitchValue(String value) => _('playbackPitchValue', {'value': value});
  String get reset => _('reset');
  String get slow => _('slow');
  String get normal => _('normal');
  String get fast => _('fast');

  String minutesLabel(int n) => _('minutesLabel', {'n': '$n'});
  String get endOfTrack => _('endOfTrack');
  String get turnOff => _('turnOff');

  String get gallery => _('gallery');
  String get changePicture => _('changePicture');
  String get pickFromGallery => _('pickFromGallery');
  String get blur => _('blur');
  String get none => _('none');
  String get full => _('full');
  String get customTheme => _('customTheme');
  String get background => _('background');
  String get accent => _('accent');

  String themeLabel(AppThemeId id) => switch (id) {
        AppThemeId.system => _('themeSystem'),
        AppThemeId.dark => _('themeDark'),
        AppThemeId.black => _('themeBlack'),
        AppThemeId.midnight => _('themeMidnight'),
        AppThemeId.light => _('themeLight'),
        AppThemeId.sand => _('themeSand'),
        AppThemeId.custom => _('themeCustom'),
        AppThemeId.gallery => _('themeGallery'),
      };

  String get unknownArtist => _('unknownArtist');
  String get unknownAlbum => _('unknownAlbum');

  String timeAgo(int modifiedMs) {
    if (modifiedMs <= 0) return _('timeRecently');
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(modifiedMs));
    if (diff.inMinutes < 1) return _('timeJustNow');
    if (diff.inHours < 1) return _('timeMinAgo', {'n': '${diff.inMinutes}'});
    if (diff.inHours < 24) return _('timeHoursAgo', {'n': '${diff.inHours}'});
    if (diff.inDays == 1) return _('timeYesterday');
    return _('timeDaysAgo', {'n': '${diff.inDays}'});
  }

  String displayArtist(String artist) =>
      artist == 'Unknown artist' || artist.isEmpty ? unknownArtist : artist;
  String displayAlbum(String album) =>
      album == 'Unknown album' || album.isEmpty ? unknownAlbum : album;
}
