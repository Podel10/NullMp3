import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../theme/app_theme.dart';

enum AppLanguage {
  english,
  russian,
  chinese;

  String get nativeName => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.russian => 'Русский',
        AppLanguage.chinese => '中文',
      };

  Locale get locale => switch (this) {
        AppLanguage.english => const Locale('en'),
        AppLanguage.russian => const Locale('ru'),
        AppLanguage.chinese => const Locale('zh', 'CN'),
      };

  static AppLanguage fromName(String? name) {
    return AppLanguage.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AppLanguage.english,
    );
  }
}

extension AppL10n on BuildContext {
  S get s => S(Provider.of<SettingsController>(this, listen: false).language);
}

class S {
  const S(this.lang);
  final AppLanguage lang;

  String _t(String en, String ru, String zh) => switch (lang) {
        AppLanguage.english => en,
        AppLanguage.russian => ru,
        AppLanguage.chinese => zh,
      };

  String get appName => 'Null MP3';
  String get settings => _t('Settings', 'Настройки', '设置');
  String get language => _t('Language', 'Язык', '语言');
  String get chooseLanguage => _t('Choose language', 'Выберите язык', '选择语言');
  String get chooseWallpaper => _t('Choose wallpaper', 'Выберите обои', '选择壁纸');
  String get selectSongs => _t('Select songs', 'Выберите песни', '选择歌曲');
  String get appearance => _t('Appearance', 'Оформление', '外观');
  String get library => _t('Library', 'Библиотека', '曲库');
  String get about => _t('About', 'О приложении', '关于');

  String get tabRecommended => _t('Recommended', 'Рекомендуется', '推荐');
  String get tabSongs => _t('Songs', 'Песни', '歌曲');
  String get tabAlbums => _t('Albums', 'Альбомы', '专辑');
  String get tabArtists => _t('Artists', 'Исполнители', '艺人');
  String get tabPlaylists => _t('Playlists', 'Плейлисты', '播放列表');
  String get tabFolders => _t('Folders', 'Папки', '文件夹');

  String get recentlyPlayed => _t('Recently played', 'Недавно прослушанные', '最近播放');
  String get mostPopular => _t('Most popular', 'Самая популярная', '最热门');
  String get favorites => _t('Favorites', 'Избранное', '收藏');
  String get recentlyAdded => _t('Recently added', 'Последние добавленные', '最近添加');
  String get mostPlayed => _t('Most played', 'Часто играемые', '常听');
  String listens(int n) => '🎧 $n';
  String get seeAll => _t('SEE ALL', 'ПОСМОТРЕТЬ ВСЕ', '查看全部');
  String get playToFill => _t('Play something to fill this page', 'Включите трек, чтобы заполнить эту страницу', '播放歌曲后这里会出现内容');

  String get search => _t('Search', 'Поиск', '搜索');
  String get searchHint => _t('Search songs, albums, artists', 'Поиск песен, альбомов, исполнителей', '搜索歌曲、专辑、艺人');
  String get searchYourLibrary => _t('Search your library', 'Ищите в своей библиотеке', '搜索曲库');
  String get noMatches => _t('No matches', 'Ничего не найдено', '无匹配结果');

  String get equalizer => _t('Equalizer', 'Эквалайзер', '均衡器');
  String get sleepTimer => _t('Sleep timer', 'Таймер сна', '睡眠定时');
  String get themeSettings => _t('Theme settings', 'Тема', '主题设置');
  String get addFolder => _t('Add folder', 'Добавить папку', '添加文件夹');
  String get addFiles => _t('Add files', 'Добавить файлы', '添加文件');
  String get sort => _t('Sort', 'Сортировка', '排序');
  String get sortTitle => _t('Title', 'Название', '标题');
  String get sortArtist => _t('Artist', 'Исполнитель', '艺人');
  String get sortAlbum => _t('Album', 'Альбом', '专辑');
  String get sortDuration => _t('Duration', 'Длительность', '时长');
  String get sortDate => _t('Date added', 'Дата добавления', '添加日期');

  String songsCount(int n) => _t('$n songs', '$n песен', '$n 首歌曲');
  String albumsCount(int n) => _t('$n albums', '$n альбомов', '$n 张专辑');
  String songsInLibrary(int n) => _t('$n songs in library', '$n песен в библиотеке', '曲库中有 $n 首歌曲');
  String albumsAndSongs(int albums, int songs) =>
      _t('$albums albums • $songs songs', '$albums альбомов • $songs песен', '$albums 张专辑 • $songs 首歌曲');
  String librarySize(int songs, int albums, int artists) => _t(
        '$songs songs • $albums albums • $artists artists',
        '$songs песен • $albums альбомов • $artists исполнителей',
        '$songs 首歌曲 • $albums 张专辑 • $artists 位艺人',
      );
  String tracksCount(int n) => _t('$n tracks', '$n треков', '$n 首');

  String get newPlaylist => _t('New playlist', 'Новый плейлист', '新建播放列表');
  String get rename => _t('Rename', 'Переименовать', '重命名');
  String get delete => _t('Delete', 'Удалить', '删除');
  String get renamePlaylist => _t('Rename playlist', 'Переименовать плейлист', '重命名播放列表');
  String get playlistRemoved => _t('Playlist removed', 'Плейлист удалён', '播放列表已删除');
  String get noSongsInPlaylist => _t('No songs in this playlist', 'В плейлисте нет песен', '播放列表为空');
  String get nothingHereYet => _t('Nothing here yet', 'Здесь пока пусто', '暂无内容');
  String get playAll => _t('Play all', 'Играть все', '全部播放');
  String get shuffle => _t('Shuffle', 'Перемешать', '随机播放');
  String get nameHint => _t('Name', 'Имя', '名称');
  String get cancel => _t('Cancel', 'Отмена', '取消');
  String get save => _t('Save', 'Сохранить', '保存');
  String get close => _t('Close', 'Закрыть', '关闭');
  String get show => _t('Show', 'Показать', '显示');
  String get off => _t('Off', 'Выкл.', '关');

  String get noMusicYet => _t('No music yet', 'Музыки пока нет', '还没有音乐');
  String get emptyLibraryHint => _t(
        'Scan your Music folder, add a directory, or pick MP3 files to start playing.',
        'Добавьте папку или файлы, чтобы начать слушать.',
        '添加文件夹或文件即可开始播放。',
      );
  String get updateLibrary => _t('Update library', 'Обновить библиотеку', '更新曲库');
  String get updatingLibrary => _t('Updating library…', 'Обновление библиотеки…', '正在更新曲库…');
  String get lookingForMusic => _t('Looking for music…', 'Поиск музыки…', '正在查找音乐…');
  String scanStatus(String? key) => switch (key) {
        'updatingLibrary' => updatingLibrary,
        'lookingForMusic' => lookingForMusic,
        _ => key ?? '',
      };

  String get alreadyInLibrary => _t('Those songs are already in the library', 'Эти песни уже в библиотеке', '这些歌曲已在曲库中');
  String addedSongs(int n) => n == 1
      ? _t('Added 1 song', 'Добавлена 1 песня', '已添加 1 首歌曲')
      : _t('Added $n songs', 'Добавлено $n песен', '已添加 $n 首歌曲');

  String get foldersHint => _t(
        'Build the library from Folders in the side menu. Download can be removed too.',
        'Соберите библиотеку в меню «Папки». Download тоже можно убрать.',
        '在侧栏的「文件夹」中管理曲库，Download 也可以移除。',
      );
  String get skipShortTracks => _t('Skip short tracks', 'Пропускать короткие треки', '跳过短音频');
  String seconds(int n) => _t('$n seconds', '$n секунд', '$n 秒');
  String get librarySizeLabel => _t('Library size', 'Размер библиотеки', '曲库规模');
  String get statistics => _t('Statistics', 'Статистика', '统计');
  String get listenTime => _t('Listening time', 'Время прослушивания', '收听时长');
  String get tracksListened => _t('Tracks listened', 'Прослушанных треков', '已听歌曲');
  String listenHours(int milliseconds) {
    final minutes = (milliseconds / 60000).floor();
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours <= 0) {
      return _t('$minutes min', '$minutes мин', '$minutes 分钟');
    }
    if (rest == 0) {
      return _t('$hours h', '$hours ч', '$hours 小时');
    }
    return _t('$hours h $rest min', '$hours ч $rest мин', '$hours 小时 $rest 分钟');
  }
  String get disableStatistics => _t('Disable statistics', 'Отключить статистику', '关闭统计');
  String get enableStatistics => _t('Enable statistics', 'Включить статистику', '开启统计');
  String get statisticsOffHint => _t(
        'Listening stats were deleted and are no longer saved.',
        'Статистика удалена и больше не сохраняется.',
        '统计已清除，不再保存。',
      );

  String get hiddenSongs => _t('Hidden songs', 'Скрытые песни', '已隐藏歌曲');
  String get nothingHidden => _t('Nothing hidden', 'Ничего не скрыто', '没有隐藏歌曲');
  String get hiddenHint => _t(
        'Hidden tracks stay on the device but disappear from the library',
        'Скрытые треки остаются на устройстве, но пропадают из библиотеки',
        '隐藏的歌曲仍留在设备上，只是不出现在曲库中',
      );
  String get aboutBlurb => _t(
        'A local music player inspired by Muzio — library tabs, mini player, now playing, equalizer, sleep timer, lyrics, and playlists.',
        'Локальный плеер в духе Muzio — вкладки библиотеки, мини-плеер, эквалайзер, таймер сна, тексты и плейлисты.',
        '受 Muzio 启发的本地播放器：曲库、迷你播放条、均衡器、睡眠定时、歌词和播放列表。',
      );

  String get libraryFolders => _t('Library folders', 'Папки библиотеки', '曲库文件夹');
  String get libraryFoldersHint =>
      _t('Add or remove any folder, including Download', 'Добавляйте и убирайте любые папки, включая Download', '可添加或移除任意文件夹，包括 Download');
  String get inLibrary => _t('In library', 'В библиотеке', '已加入曲库');
  String get nothingSelected => _t('Nothing selected', 'Ничего не выбрано', '尚未选择');
  String get tapFolderBelow => _t('Tap a folder below to start building the library', 'Нажмите папку ниже, чтобы собрать библиотеку', '点下方文件夹开始建立曲库');
  String get foldersWithMostTracks => _t('Folders with the most tracks', 'Папки с наибольшим числом треков', '曲目最多的文件夹');
  String get noFoldersFound => _t('No folders found', 'Папки не найдены', '未找到文件夹');
  String get allFoldersAdded => _t('All found folders are already added', 'Все найденные папки уже добавлены', '找到的文件夹都已添加');
  String get pickFolderYourself => _t('Use the folder button to pick one yourself', 'Выберите папку кнопкой сверху', '点右上角按钮自行选择文件夹');
  String addedFolder(String name) => _t('Added $name', 'Добавлено: $name', '已添加 $name');
  String removedFolder(String name) => _t('Removed $name', 'Удалено: $name', '已移除 $name');
  String tracksInPath(int count, String path) => _t('$count tracks • $path', '$count треков • $path', '$count 首 • $path');

  String get nothingPlaying => _t('Nothing is playing', 'Ничего не играет', '当前没有播放');
  String get playingFrom => _t('Playing from', 'Воспроизводится из', '来自');
  String get repeatTrack => _t('Repeat track', 'Повтор трека', '单曲循环');
  String get previousTrack => _t('Previous track', 'Предыдущий трек', '上一首');
  String get nextTrack => _t('Next track', 'Следующий трек', '下一首');
  String get pause => _t('Pause', 'Пауза', '暂停');
  String get play => _t('Play', 'Играть', '播放');
  String get shuffleOn => _t('Shuffle on', 'Перемешивание включено', '随机播放已开');
  String get shuffleOff => _t('Shuffle', 'Перемешать', '随机播放');

  String get lyrics => _t('Lyrics', 'Текст песни', '歌词');
  String get lyricsNotFound => _t('Lyrics not found', 'Текст не найден', '未找到歌词');
  String get lyricsNotFoundHint => _t(
        'Search online or paste the lyrics here. Nothing is written into the original file.',
        'Найдите текст в сети или вставьте его сюда. В исходный файл ничего не пишется.',
        '可在线搜索或在此粘贴歌词。不会写入原始文件。',
      );
  String get lyricsSearchOnline => _t('Search online', 'Найти в сети', '在线搜索');
  String get lyricsWrite => _t('Write lyrics', 'Написать текст', '填写歌词');
  String get lyricsHint => _t(
        'Paste lyrics. Lines like [00:12.00]Hello become karaoke timing.',
        'Вставьте текст. Строки вида [00:12.00]Привет станут караоке.',
        '粘贴歌词。形如 [00:12.00]你好 的行会变成逐句同步。',
      );
  String get lyricsSearching => _t('Looking for lyrics…', 'Ищем текст…', '正在查找歌词…');
  String get lyricsSearchFailed => _t('Could not find lyrics', 'Не удалось найти текст', '未找到歌词');
  String get lyricsSearchHint => _t(
        'Type the original artist and title. Mixes and SoundCloud rips rarely have their own lyrics.',
        'Введите оригинального исполнителя и название. У миксов и рипов со SoundCloud своего текста обычно нет.',
        '请输入原曲艺人和歌名。混音和 SoundCloud 转存通常没有独立歌词。',
      );
  String get lyricsFilterDuration => _t('Similar length', 'Похожая длина', '时长接近');
  String get lyricsFilterArtist => _t('Same artist', 'Тот же исполнитель', '相同艺人');
  String get lyricsFilterSynced => _t('Timed lines', 'С таймингом', '逐句同步');
  String get lyricsPickResult => _t('Pick the right lyrics', 'Выберите нужный текст', '选择正确歌词');
  String lyricsHitMeta(String artist, String duration, String source) =>
      '$artist • $duration • $source';
  String get lyricsOffline => _t('No internet connection', 'Нет интернета', '没有网络');
  String get lyricsOfflineHint => _t(
        'Connect to the internet to search, or paste the lyrics yourself.',
        'Подключитесь к сети, чтобы искать, или вставьте текст сами.',
        '请联网后搜索，或自行粘贴歌词。',
      );
  String get editLyrics => _t('Edit lyrics', 'Править текст', '编辑歌词');
  String get clearLyrics => _t('Clear', 'Очистить', '清除');
  String get instrumental => _t('Instrumental', 'Инструментал', '纯音乐');
  String get autoStyle => _t('Auto style', 'Автостиль', '自动封面');
  String get coverSearchHint => _t(
        'Search the pictures people use for this track on YouTube, iTunes, and Deezer.',
        'Ищем обложки, которые ставят на этот трек на YouTube, iTunes и Deezer.',
        '搜索 YouTube、iTunes、Deezer 上这首歌常用的封面。',
      );
  String get coverSearchSources => _t(
        'YouTube thumbnails plus catalog artwork. Saved locally, not into the file.',
        'Превью с YouTube и обложки из каталогов. Сохраняется локально, не в файл.',
        '来自 YouTube 缩略图和曲库封面。仅保存在本地，不写入文件。',
      );
  String get searchImage => _t('Search image', 'Поиск картинки', '搜索图片');
  String get searchGif => _t('Search GIF', 'Поиск GIF', '搜索 GIF');
  String get imageSearchHint => _t(
        'Type anything — Pinterest, not the track.',
        'Напишите что найти в Pinterest, не обязательно про трек.',
        '随便输入，在 Pinterest 搜图，不必跟歌曲有关。',
      );
  String get imageSearchSources => _t(
        'Pinterest pictures. Saved locally, not into the file.',
        'Картинки с Pinterest. Сохраняется локально, не в файл.',
        '来自 Pinterest 的图片。仅保存在本地，不写入文件。',
      );
  String get gifSearchHint => _t(
        'Type anything — GIFs from Tenor, Giphy, Bing, and Pinterest.',
        'Напишите что найти: GIF с Tenor, Giphy, Bing и Pinterest.',
        '随便输入，从 Tenor、Giphy、Bing、Pinterest 搜 GIF。',
      );
  String get gifSearchSources => _t(
        'Tenor, Giphy, Bing, and Pinterest. Motion is kept. Saved locally, not into the file.',
        'Tenor, Giphy, Bing и Pinterest. Движение сохраняется. Сохраняется локально, не в файл.',
        '来自 Tenor、Giphy、Bing 和 Pinterest。保留动画，仅保存在本地，不写入文件。',
      );
  String get coverSearchFailed => _t('No covers found', 'Обложки не найдены', '未找到封面');
  String get coverSearchApplyFailed => _t('Could not save this cover', 'Не удалось сохранить обложку', '无法保存封面');
  String get cropCover => _t('Crop cover', 'Обрезать обложку', '裁剪封面');
  String get cropCoverHint => _t(
        'Drag a square. Only the selected part stays on the cover.',
        'Выдели квадрат — на обложке останется только эта область.',
        '拖出一个正方形，封面只保留选中的部分。',
      );
  String get coverApplied => _t('Cover updated', 'Обложка обновлена', '封面已更新');
  String get addToPlaylist => _t('Add to playlist', 'Добавить в плейлист', '添加到播放列表');
  String get addToPlaylistEllipsis => _t('Add to playlist…', 'Добавить в плейлист…', '添加到播放列表…');
  String get tagEditor => _t('Display settings', 'Настройка отображения', '显示设置');
  String get displaySettings => _t('Display settings', 'Настройка отображения', '显示设置');
  String get coverShape => _t('Cover shape', 'Форма обложки', '封面形状');
  String get shapeSquare => _t('Square', 'Квадрат', '方形');
  String get shapeCircle => _t('Circle', 'Круг', '圆形');
  String get beatHalo => _t('Beat waves', 'Волны под бит', '节拍光环');
  String get beatHaloHint => _t(
        'Pulses with the playing audio. Android may ask for the microphone — that is how the system reads the player spectrum, it is not recording.',
        'Пульсирует по реальному звуку. Android может спросить микрофон — так система отдаёт спектр плеера, запись не идёт.',
        '随正在播放的音频脉冲。Android 可能请求麦克风权限——系统用它读取播放器频谱，并不会录音。',
      );
  String get details => _t('Details', 'Подробнее', '详情');
  String get playbackSpeed => _t('Playback speed', 'Скорость воспроизведения', '播放速度');
  String get musicEditor => _t('Music editor', 'Редактор музыки', '音乐编辑');
  String get ringtoneEditor => musicEditor;
  String selectionMeta(double seconds, String format, int sampleRate, int bitrate) {
    final sec = seconds.toStringAsFixed(2);
    return _t(
      '$sec s selected. $format, $sampleRate Hz, $bitrate kbps',
      '$sec с выбрано. $format, $sampleRate Hz, $bitrate kbps',
      '已选 $sec 秒。$format，$sampleRate Hz，$bitrate kbps',
    );
  }
  String cutSaved(String title) => _t('Saved "$title"', 'Сохранено «$title»', '已保存“$title”');
  String get cutFailed => _t('Could not save the cut', 'Не удалось сохранить обрезанный файл', '无法保存剪辑');
  String get drivingMode => _t('Driving mode', 'Режим «За рулём»', '驾驶模式');
  String get lockScreen => _t('Lock screen', 'Экран блокировки', '锁屏播放');
  String get lockedHint => _t(
        'Hold to unlock',
        'Удерживайте, чтобы разблокировать',
        '长按解锁',
      );
  String get lockNow => _t('Lock', 'Заблокировать', '锁定');
  String get hide => _t('Hide', 'Скрыть', '隐藏');
  String get deleteFromDevice => _t('Delete from device', 'Удалить с устройства', '从设备删除');
  String get share => _t('Share', 'Поделиться', '分享');
  String get preparingShare => _t('Preparing file…', 'Готовим файл…', '正在准备文件…');
  String get removeFromPlaylist => _t('Remove from playlist', 'Убрать из плейлиста', '从播放列表移除');
  String get playPauseFade => _t('Play/Pause fade', 'Играть/Пауза', '播放/暂停淡化');
  String get milliseconds300 => _t('300 milliseconds', '300 миллисекунд', '300 毫秒');
  String get crossfade => _t('Crossfade', 'Плавный переход', '交叉淡化');

  String get hideTrack => _t('Hide track', 'Скрыть трек', '隐藏歌曲');
  String hideTrackBody(String title) => _t(
        '"$title" will disappear from the library. The file stays on the device.',
        '«$title» исчезнет из библиотеки. Файл на устройстве останется.',
        '“$title”将从曲库中消失，文件仍保留在设备上。',
      );
  String get hiddenFromLibrary => _t('Hidden from library', 'Скрыто из библиотеки', '已从曲库隐藏');
  String deleteFileBody(String title) => _t(
        'The file "$title" will be deleted. This cannot be undone.',
        'Файл «$title» будет удалён. Это нельзя отменить.',
        '文件“$title”将被删除，无法恢复。',
      );
  String get fileDeleted => _t('File deleted', 'Файл удалён', '文件已删除');
  String deleteFailed(String error) => _t('Could not delete: $error', 'Не удалось удалить: $error', '无法删除：$error');
  String shareFailed(String error) => _t('Could not share: $error', 'Не удалось поделиться: $error', '无法分享：$error');
  String get deleteCancelled => _t('Delete cancelled', 'Удаление отменено', '已取消删除');
  String get deleteNeedPermission => _t(
        'Could not delete the file. Confirm in the system dialog or give Null MP3 all-files access.',
        'Не удалось удалить файл. Подтвердите удаление в системном окне или выдайте Null MP3 доступ ко всем файлам.',
        '无法删除文件。请在系统对话框中确认，或授予 Null MP3 所有文件访问权限。',
      );
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

  String get cover => _t('Cover', 'Обложка', '封面');
  String get changeCover => _t('Change cover', 'Сменить обложку', '更换封面');
  String get changeCoverHint => _t('Photo, GIF or video', 'Фото, GIF или видео', '图片、GIF 或视频');
  String get pickCoverFailed => _t(
        'Could not load that image or GIF.',
        'Не удалось загрузить изображение или GIF.',
        '无法加载该图片或 GIF。',
      );
  String saveTagsFailed(String error) => _t('Could not save: $error', 'Не удалось сохранить: $error', '无法保存：$error');
  String get tagsSaved => _t('Tags saved', 'Теги сохранены', '标签已保存');
  String get tagsSavedRenamed => _t('Tags saved, file renamed', 'Теги сохранены, файл переименован', '标签已保存，文件已重命名');
  String get fieldTitle => _t('Title', 'Заголовок', '标题');
  String get fieldAlbum => _t('Album', 'Альбом', '专辑');
  String get fieldArtist => _t('Artist', 'Исполнитель', '艺人');
  String get fieldAlbumArtist => _t('Album artist', 'Альбом исполнителя', '专辑艺人');
  String get fieldComposer => _t('Composer', 'Композитор', '作曲');
  String get trackDetails => _t('Track details', 'О треке', '歌曲详情');
  String get fieldGenre => _t('Genre', 'Жанр', '流派');
  String get fieldYear => _t('Year', 'Год', '年份');
  String get fieldDuration => _t('Duration', 'Длительность', '时长');
  String get fieldPath => _t('Path', 'Путь', '路径');

  String get enableEqualizer => _t('Enable equalizer', 'Включить эквалайзер', '启用均衡器');
  String get equalizerHint => _t(
        'Applies natively on Android. Presets are saved on every device.',
        'На Android применяется системно. Пресеты сохраняются на устройстве.',
        '在 Android 上使用系统均衡器。预设会保存在本机。',
      );
  String get eqCustom => _t('Custom', 'Своя', '自定义');
  String eqPreset(String name) => switch (name) {
        'Normal' => _t('Normal', 'Обычный', '普通'),
        'Pop' => _t('Pop', 'Поп', '流行'),
        'Rock' => _t('Rock', 'Рок', '摇滚'),
        'Jazz' => _t('Jazz', 'Джаз', '爵士'),
        'Classical' => _t('Classical', 'Классика', '古典'),
        'Dance' => _t('Dance', 'Танцы', '舞曲'),
        'Bass boost' => _t('Bass boost', 'Больше баса', '低音增强'),
        'Treble boost' => _t('Treble boost', 'Больше верхов', '高音增强'),
        'Vocal' => _t('Vocal', 'Вокал', '人声'),
        'Flat' => _t('Flat', 'Ровный', '平坦'),
        'Custom' => eqCustom,
        _ => name,
      };

  String playbackSpeedValue(String value) =>
      _t('Playback speed: ${value}x', 'Скорость воспроизведения: ${value}x', '播放速度：${value}x');
  String playbackPitchValue(String value) =>
      _t('Playback pitch: $value', 'Тон воспроизведения: $value', '音调：$value');
  String get reset => _t('Reset', 'Сброс', '重置');
  String get slow => _t('Slow', 'Медленно', '慢');
  String get normal => _t('Normal', 'Стандартно', '标准');
  String get fast => _t('Fast', 'Быстро', '快');

  String minutesLabel(int n) => _t('$n minutes', '$n минут', '$n 分钟');
  String get endOfTrack => _t('End of track', 'Конец трека', '播完当前歌曲');
  String get turnOff => _t('Turn off', 'Выключить', '关闭');

  String get gallery => _t('Gallery', 'Галерея', '图库');
  String get changePicture => _t('Change picture', 'Сменить картинку', '更换图片');
  String get pickFromGallery => _t('Choose from gallery', 'Выбрать из галереи', '从图库选择');
  String get blur => _t('Blur', 'Размытие', '模糊');
  String get none => _t('None', 'Нет', '无');
  String get full => _t('Full', 'Полное', '最大');
  String get customTheme => _t('Custom theme', 'Своя тема', '自定义主题');
  String get background => _t('Background', 'Фон', '背景');
  String get accent => _t('Accent', 'Акцент', '强调色');

  String themeLabel(AppThemeId id) => switch (id) {
        AppThemeId.system => _t('System', 'Система', '系统'),
        AppThemeId.dark => _t('Dark', 'Тёмная', '深色'),
        AppThemeId.black => _t('Black', 'Чёрная', '纯黑'),
        AppThemeId.midnight => _t('Midnight', 'Ночная', '午夜'),
        AppThemeId.light => _t('Light', 'Светлая', '浅色'),
        AppThemeId.sand => _t('Sand', 'Песочная', '沙色'),
        AppThemeId.custom => _t('Custom', 'Своя', '自定义'),
        AppThemeId.gallery => _t('Gallery', 'Галерея', '图库'),
      };

  String get unknownArtist => _t('Unknown artist', 'Неизвестный исполнитель', '未知艺人');
  String get unknownAlbum => _t('Unknown album', 'Неизвестный альбом', '未知专辑');

  String timeAgo(int modifiedMs) {
    if (modifiedMs <= 0) return _t('Recently', 'Недавно', '最近');
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(modifiedMs));
    if (diff.inMinutes < 1) return _t('Just now', 'Только что', '刚刚');
    if (diff.inHours < 1) {
      final n = diff.inMinutes;
      return _t('$n min ago', '$n мин. назад', '$n 分钟前');
    }
    if (diff.inHours < 24) {
      final n = diff.inHours;
      return _t('$n hours ago', '$n ч. назад', '$n 小时前');
    }
    if (diff.inDays == 1) return _t('Yesterday', 'Вчера', '昨天');
    return _t('${diff.inDays} days ago', '${diff.inDays} дн. назад', '${diff.inDays} 天前');
  }

  String displayArtist(String artist) =>
      artist == 'Unknown artist' || artist.isEmpty ? unknownArtist : artist;
  String displayAlbum(String album) =>
      album == 'Unknown album' || album.isEmpty ? unknownAlbum : album;
}
