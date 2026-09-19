import 'package:flutter/material.dart';

class AppLanguage {
  const AppLanguage(this.code, this.nativeName, this.locale);

  final String code;
  final String nativeName;
  final Locale locale;

  String get name => code;

  static const english = AppLanguage('en', 'English', Locale('en'));
  static const russian = AppLanguage('ru', 'Русский', Locale('ru'));
  static const chinese = AppLanguage('zh', '中文', Locale('zh', 'CN'));

  static const all = <AppLanguage>[
    english,
    AppLanguage('zh', '中文', Locale('zh', 'CN')),
    AppLanguage('zh_TW', '繁體中文', Locale('zh', 'TW')),
    AppLanguage('hi', 'हिन्दी', Locale('hi')),
    AppLanguage('es', 'Español', Locale('es')),
    AppLanguage('ar', 'العربية', Locale('ar')),
    AppLanguage('fr', 'Français', Locale('fr')),
    AppLanguage('bn', 'বাংলা', Locale('bn')),
    AppLanguage('pt', 'Português', Locale('pt', 'BR')),
    AppLanguage('pt_PT', 'Português (Portugal)', Locale('pt', 'PT')),
    russian,
    AppLanguage('ur', 'اردو', Locale('ur')),
    AppLanguage('id', 'Bahasa Indonesia', Locale('id')),
    AppLanguage('de', 'Deutsch', Locale('de')),
    AppLanguage('ja', '日本語', Locale('ja')),
    AppLanguage('sw', 'Kiswahili', Locale('sw')),
    AppLanguage('mr', 'मराठी', Locale('mr')),
    AppLanguage('te', 'తెలుగు', Locale('te')),
    AppLanguage('tr', 'Türkçe', Locale('tr')),
    AppLanguage('ta', 'தமிழ்', Locale('ta')),
    AppLanguage('vi', 'Tiếng Việt', Locale('vi')),
    AppLanguage('ko', '한국어', Locale('ko')),
    AppLanguage('it', 'Italiano', Locale('it')),
    AppLanguage('th', 'ไทย', Locale('th')),
    AppLanguage('gu', 'ગુજરાતી', Locale('gu')),
    AppLanguage('fa', 'فارسی', Locale('fa')),
    AppLanguage('pl', 'Polski', Locale('pl')),
    AppLanguage('uk', 'Українська', Locale('uk')),
    AppLanguage('ro', 'Română', Locale('ro')),
    AppLanguage('nl', 'Nederlands', Locale('nl')),
    AppLanguage('el', 'Ελληνικά', Locale('el')),
    AppLanguage('cs', 'Čeština', Locale('cs')),
    AppLanguage('sv', 'Svenska', Locale('sv')),
    AppLanguage('hu', 'Magyar', Locale('hu')),
    AppLanguage('he', 'עברית', Locale('he')),
    AppLanguage('ms', 'Bahasa Melayu', Locale('ms')),
    AppLanguage('fil', 'Filipino', Locale('fil')),
    AppLanguage('pa', 'ਪੰਜਾਬੀ', Locale('pa')),
    AppLanguage('kn', 'ಕನ್ನಡ', Locale('kn')),
    AppLanguage('ml', 'മലയാളം', Locale('ml')),
    AppLanguage('my', 'မြန်မာ', Locale('my')),
    AppLanguage('ha', 'Hausa', Locale('ha')),
    AppLanguage('jv', 'Basa Jawa', Locale('jv')),
    AppLanguage('da', 'Dansk', Locale('da')),
    AppLanguage('fi', 'Suomi', Locale('fi')),
    AppLanguage('nb', 'Norsk', Locale('nb')),
    AppLanguage('sk', 'Slovenčina', Locale('sk')),
    AppLanguage('bg', 'Български', Locale('bg')),
    AppLanguage('hr', 'Hrvatski', Locale('hr')),
    AppLanguage('sr', 'Српски', Locale('sr')),
    AppLanguage('ca', 'Català', Locale('ca')),
    AppLanguage('lt', 'Lietuvių', Locale('lt')),
    AppLanguage('lv', 'Latviešu', Locale('lv')),
    AppLanguage('et', 'Eesti', Locale('et')),
    AppLanguage('sl', 'Slovenščina', Locale('sl')),
    AppLanguage('kk', 'Қазақша', Locale('kk')),
    AppLanguage('uz', 'Oʻzbekcha', Locale('uz')),
    AppLanguage('az', 'Azərbaycan', Locale('az')),
    AppLanguage('ka', 'ქართული', Locale('ka')),
    AppLanguage('hy', 'Հայերեն', Locale('hy')),
    AppLanguage('km', 'ខ្មែរ', Locale('km')),
    AppLanguage('lo', 'ລາວ', Locale('lo')),
    AppLanguage('ne', 'नेपाली', Locale('ne')),
    AppLanguage('si', 'සිංහල', Locale('si')),
    AppLanguage('mn', 'Монгол', Locale('mn')),
    AppLanguage('sq', 'Shqip', Locale('sq')),
    AppLanguage('mk', 'Македонски', Locale('mk')),
    AppLanguage('bs', 'Bosanski', Locale('bs')),
    AppLanguage('is', 'Íslenska', Locale('is')),
    AppLanguage('af', 'Afrikaans', Locale('af')),
    AppLanguage('zu', 'isiZulu', Locale('zu')),
    AppLanguage('am', 'አማርኛ', Locale('am')),
    AppLanguage('yo', 'Yorùbá', Locale('yo')),
    AppLanguage('ig', 'Igbo', Locale('ig')),
    AppLanguage('so', 'Soomaali', Locale('so')),
    AppLanguage('ps', 'پښتو', Locale('ps')),
    AppLanguage('be', 'Беларуская', Locale('be')),
    AppLanguage('eu', 'Euskara', Locale('eu')),
    AppLanguage('gl', 'Galego', Locale('gl')),
    AppLanguage('as', 'অসমীয়া', Locale('as')),
    AppLanguage('or', 'ଓଡ଼ିଆ', Locale('or')),
    AppLanguage('cy', 'Cymraeg', Locale('cy')),
    AppLanguage('ga', 'Gaeilge', Locale('ga')),
    AppLanguage('ceb', 'Cebuano', Locale('ceb')),
    AppLanguage('ht', 'Kreyòl ayisyen', Locale('ht')),
    AppLanguage('tg', 'Тоҷикӣ', Locale('tg')),
    AppLanguage('ky', 'Кыргызча', Locale('ky')),
    AppLanguage('tk', 'Türkmençe', Locale('tk')),
    AppLanguage('tt', 'Татарча', Locale('tt')),
    AppLanguage('mg', 'Malagasy', Locale('mg')),
    AppLanguage('xh', 'isiXhosa', Locale('xh')),
    AppLanguage('sn', 'chiShona', Locale('sn')),
    AppLanguage('ku', 'Kurdî', Locale('ku')),
  ];

  static List<AppLanguage> get values => all;

  static const _legacy = {
    'english': english,
    'russian': russian,
    'chinese': chinese,
  };

  static AppLanguage fromName(String? name) {
    if (name == null || name.isEmpty) return english;
    final legacy = _legacy[name];
    if (legacy != null) return legacy;
    return all.firstWhere((item) => item.code == name, orElse: () => english);
  }

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
