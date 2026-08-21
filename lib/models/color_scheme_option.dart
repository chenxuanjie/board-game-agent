enum ColorSchemeOption { classic, sunsetCoast }

extension ColorSchemeOptionX on ColorSchemeOption {
  String get code {
    switch (this) {
      case ColorSchemeOption.classic:
        return 'classic';
      case ColorSchemeOption.sunsetCoast:
        return 'sunset_coast';
    }
  }

  static ColorSchemeOption fromCode(String? code) {
    switch (code) {
      case 'classic':
        return ColorSchemeOption.classic;
      case 'sunset_coast':
        return ColorSchemeOption.sunsetCoast;
      default:
        return ColorSchemeOption.classic;
    }
  }
}
