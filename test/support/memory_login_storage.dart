import 'package:app_identity/app_identity.dart';

class MemoryLoginStorage implements IdentitySessionStorage {
  String? value;
  bool failRead = false, failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('synthetic storage failure');
    return value;
  }

  @override
  Future<void> write(String next) async {
    if (failWrite) throw StateError('synthetic storage failure');
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
