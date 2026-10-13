enum ColorSchemeOption { classic, cinema, warmwoodStudy }

const ColorSchemeOption defaultColorScheme = ColorSchemeOption.warmwoodStudy;

extension ColorSchemeOptionX on ColorSchemeOption {
  String get code {
    switch (this) {
      case ColorSchemeOption.classic:
        return 'classic';
      case ColorSchemeOption.cinema:
        return 'cinema';
      case ColorSchemeOption.warmwoodStudy:
        return 'warmwood_study';
    }
  }

  static ColorSchemeOption fromCode(String? code) {
    switch (code?.trim().toLowerCase()) {
      case 'classic':
        return ColorSchemeOption.classic;
      case 'cinema':
      case '影院':
        return ColorSchemeOption.cinema;
      case 'warmwood_study':
      case 'warmwoodstudy':
      case 'warmwood-study':
      case '暖木书房':
        return ColorSchemeOption.warmwoodStudy;
      default:
        return defaultColorScheme;
    }
  }
}
