enum ColorSchemeOption {
  classic,
  gradientBluePink,
}

extension ColorSchemeOptionX on ColorSchemeOption {
  String get code {
    switch (this) {
      case ColorSchemeOption.classic:
        return 'classic';
      case ColorSchemeOption.gradientBluePink:
        return 'gradient_blue_pink';
    }
  }

  static ColorSchemeOption fromCode(String? code) {
    switch (code) {
      case 'gradient_blue_pink':
        return ColorSchemeOption.gradientBluePink;
      case 'classic':
      default:
        return ColorSchemeOption.classic;
    }
  }
}
