enum AppLanguage { zhHans, en }

extension AppLanguageX on AppLanguage {
  String get code {
    switch (this) {
      case AppLanguage.zhHans:
        return 'zh-Hans';
      case AppLanguage.en:
        return 'en';
    }
  }

  String get speechLocale {
    switch (this) {
      case AppLanguage.zhHans:
        return 'zh_CN';
      case AppLanguage.en:
        return 'en_US';
    }
  }

  String get label {
    switch (this) {
      case AppLanguage.zhHans:
        return '简体中文';
      case AppLanguage.en:
        return 'English';
    }
  }

  String get shortLabel {
    switch (this) {
      case AppLanguage.zhHans:
        return '中';
      case AppLanguage.en:
        return 'EN';
    }
  }

  static AppLanguage fromCode(String? code) {
    switch (code) {
      case 'en':
        return AppLanguage.en;
      case 'zh-Hans':
      default:
        return AppLanguage.zhHans;
    }
  }
}
