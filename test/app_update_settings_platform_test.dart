import 'support/catalog_fixture.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/features/assistant/services/ai_service.dart';
import 'package:board_game_agent/features/assistant/services/speech_service.dart';
import 'package:board_game_agent/features/assistant/services/tts_service.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/desktop/desktop_responsive.dart';
import 'package:board_game_agent/ui/desktop/settings_pane.dart';
import 'package:board_game_agent/ui/mobile/settings_screen.dart';
import 'package:board_game_agent/ui/shared/library_check_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAi extends Fake implements AiService {}

class _NoTts extends TtsService {
  @override
  bool get isAvailable => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'settings expose native updates only and retain library checks at $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final controller = AppController(
          preferencesService: PreferencesService(),
          aiService: _NoAi(),
          gameManifestService: FixtureGameManifestService(),
          remoteAssetService: RemoteAssetService(),
          speechService: SpeechService(),
          ttsService: _NoTts(),
        );
        addTearDown(controller.dispose);
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var about = 0, updates = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildTheme(controller.palette),
            home: width < 700
                ? MobileSettingsScreen(
                    controller: controller,
                    onOpenAbout: () => about++,
                  )
                : Scaffold(
                    body: DesktopMetricsScope(
                      metrics: DesktopResponsive.metricsFor(Size(width, 900)),
                      child: SingleChildScrollView(
                        child: DesktopSettingsPane(
                          controller: controller,
                          onOpenAbout: () => about++,
                          onCheckUpdates: () => updates++,
                        ),
                      ),
                    ),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LibraryCheckActions), findsOneWidget);
        expect(
          find.text(controller.copy.checkForUpdatesTitle),
          kIsWeb ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('当前更新源仅支持 Android APK'),
          kIsWeb || width < 700 ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('desktop-settings-check-updates')),
          !kIsWeb && width >= 700 ? findsOneWidget : findsNothing,
        );
        if (kIsWeb) expect(find.text('关于与更新'), findsNothing);
        final aboutButton = find.byKey(
          ValueKey(
            width < 700
                ? 'mobile-settings-about'
                : 'desktop-settings-open-about',
          ),
        );
        await tester.ensureVisible(aboutButton);
        await tester.tap(aboutButton);
        await tester.pumpAndSettle();
        expect(about, 1);
        expect(updates, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
