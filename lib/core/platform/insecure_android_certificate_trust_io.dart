import 'dart:io';

void enableInsecureAndroidCertificateTrust() {
  if (!Platform.isAndroid) return;
  HttpOverrides.global = _InsecureAndroidHttpOverrides();
}

final class _InsecureAndroidHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // Temporary private-use mode: trust every HTTPS certificate on Android.
    client.badCertificateCallback = (_, _, _) => true;
    return client;
  }
}
