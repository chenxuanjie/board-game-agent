enum ColorSchemeOption { cinema, warmwoodStudy, spatialCinema }

const ColorSchemeOption defaultColorScheme = ColorSchemeOption.warmwoodStudy;

extension ColorSchemeOptionX on ColorSchemeOption {
  String get code {
    switch (this) {
      case ColorSchemeOption.cinema:
        return 'cinema';
      case ColorSchemeOption.spatialCinema:
        return 'spatial_cinema';
      case ColorSchemeOption.warmwoodStudy:
        return 'warmwood_study';
    }
  }

  static ColorSchemeOption fromCode(String? code) {
    switch (code?.trim().toLowerCase()) {
      case 'spatial_cinema':
      case '空间影院':
        return ColorSchemeOption.spatialCinema;
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
