import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/app/state/app_controller.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/core/models/connectivity_status.dart';
import 'package:board_game_agent/core/theme/app_theme.dart';
import 'package:board_game_agent/core/theme/palette_registry.dart';
import 'package:board_game_agent/features/assistant/models/ai_conversation.dart';
import 'package:board_game_agent/features/games/models/game_info.dart';
import 'package:board_game_agent/features/games/models/recent_game_record.dart';
import 'package:board_game_agent/features/identity/services/account_service.dart';
import 'package:board_game_agent/features/identity/services/reaction_sync_diagnostics.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/account_scope.dart';
import 'package:board_game_agent/ui/shared/account_screen.dart';
import 'package:board_game_agent/ui/shared/account_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'support/memory_login_storage.dart';

part 'account/account_menu_test_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  _registerAccountMenuTests();
}

Future<void> _mount(
  WidgetTester tester,
  AccountService service, {
  Widget home = const AccountScreen(),
  ThemeData? theme,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    AccountScope(
      service: service,
      child: MaterialApp(
        theme: theme ?? AppTheme.buildTheme(PaletteRegistry.cinema),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MineFixture extends ChangeNotifier implements AppController {
  @override
  final reactionDiagnostics = ReactionSyncDiagnostics();
  final _votes = GameVoteService(preferences: PreferencesService());
  final _likes = GameVoteService(preferences: PreferencesService());
  @override
  GameVoteService get gameVotes => _votes;
  @override
  GameVoteService get favoriteStatistics => _likes;
  @override
  void dispose() {
    reactionDiagnostics.dispose();
    _votes.dispose();
    _likes.dispose();
    super.dispose();
  }

  @override
  ConnectivityStatus get assetConnectivityStatus =>
      ConnectivityStatus.unknown();
  @override
  Map<String, ConnectivityStatus> get assetSourceStatuses => {};
  @override
  List<AssetSourceConfig> get assetSourceConfigs => AssetSourceConfig.defaults;
  @override
  bool get accountCloudIdle => false;
  @override
  bool get canStartPrivateCloudSync => false;
  @override
  AppCopy get copy => AppCopy(AppLanguage.zhHans);
  @override
  List<GameInfo> get recentlyViewedGames => [];
  @override
  List<RecentGameRecord> get recentGameRecords => [];
  @override
  List<AiConversation> get conversations => [];
  @override
  int get favoriteCount => 0;
  @override
  int get unreadActivityCount => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Real account/controller wiring with a deterministic gateway; no live login.
Future<(AccountService, _UiGateway)> _configuredService(
  WidgetTester tester, {
  bool signedIn = false,
  bool offline = false,
}) async {
  final result = await tester.runAsync(() async {
    final controller = _MineFixture();
    final gateway = _UiGateway()
      ..current = signedIn
          ? const IdentityUser(id: 'fixture-user', displayName: 'Shane')
          : null
      ..offline = offline;
    final service = AccountService(
      savedLoginStorage: MemoryLoginStorage(),
      controller: controller,
      gatewayFactory: (_) async => gateway,
      switchScope: (_) async {},
    );
    await service.configureService('https://service.example.test');
    await service.restore();
    await service.loadSavedLogins();
    return (service, gateway, controller);
  });
  final (service, gateway, controller) = result!;
  addTearDown(() async {
    service.dispose();
    controller.dispose();
    await gateway.events.close();
  });
  return (service, gateway);
}

class _UiGateway implements IdentityGateway, IdentityLocalSessionCleanup {
  final events = StreamController<IdentityEvent>.broadcast();
  IdentityUser? current;
  bool offline = false;
  int signInCalls = 0;
  int signOutCalls = 0;
  int verifyCalls = 0;
  Completer<void>? signOutGate;
  Completer<IdentityUser>? signInGate;
  bool failSignOut = false;

  @override
  IdentityUser? get cachedUser => current;
  @override
  Stream<IdentityEvent> get changes => events.stream;

  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    signInCalls++;
    if (signInGate != null) return signInGate!.future;
    if (otp == null) {
      throw const IdentityFailure(IdentityFailureCode.otpRequired);
    }
    return current = const IdentityUser(
      id: 'fixture-user',
      displayName: 'Shane',
    );
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() async {
    verifyCalls++;
    if (offline) throw const IdentityFailure(IdentityFailureCode.network);
    return current;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await signOutGate?.future;
    if (failSignOut) throw const IdentityFailure(IdentityFailureCode.network);
    await clearLocalSession();
  }

  @override
  Future<void> clearLocalSession() async {
    current = null;
    events.add(const IdentityEvent(type: IdentityEventType.signedOut));
  }

  @override
  void cancelRequests() {
    final pending = signInGate;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const IdentityFailure(IdentityFailureCode.cancelled),
      );
    }
  }

  @override
  Future<void> dispose() async {}
}
