enum ColorSchemeOption { classic, sunsetCoast, warmwoodStudy }

extension ColorSchemeOptionX on ColorSchemeOption {
  String get code {
    switch (this) {
      case ColorSchemeOption.classic:
        return 'classic';
      case ColorSchemeOption.sunsetCoast:
        return 'sunset_coast';
      case ColorSchemeOption.warmwoodStudy:
        return 'warmwood_study';
    }
  }

  static ColorSchemeOption fromCode(String? code) {
    switch (code) {
      case 'classic':
        return ColorSchemeOption.classic;
      case 'sunset_coast':
        return ColorSchemeOption.sunsetCoast;
      case 'warmwood_study':
        return ColorSchemeOption.warmwoodStudy;
      default:
        return ColorSchemeOption.classic;
    }
  }
}
