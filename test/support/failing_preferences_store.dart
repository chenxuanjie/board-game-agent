import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Reject actual plugin writes, independently of SharedPreferences' cache.
class FailingPreferencesStore extends InMemorySharedPreferencesStore {
  FailingPreferencesStore() : super.empty();

  bool Function(String key) reject = (_) => false;
  bool throwOnRejection = true;
  Future<void> Function(String key)? beforeWrite;
  final attempts = <String>[];

  void install() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = this;
  }

  Future<bool> _write(String key, Future<bool> Function() action) async {
    attempts.add(key);
    await beforeWrite?.call(key);
    if (reject(key)) {
      if (throwOnRejection) throw StateError('Injected local write failure');
      return false;
    }
    return action();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _write(key, () => super.setValue(valueType, key, value));

  @override
  Future<bool> remove(String key) => _write(key, () => super.remove(key));
}
