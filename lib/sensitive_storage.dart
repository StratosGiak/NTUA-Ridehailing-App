import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum LoginInfo { id, name, token }

class SecureStorage {
  static const storage = FlutterSecureStorage();

  static Future<void> storeValueSecure(LoginInfo key, String value) async =>
      storage.write(key: key.name, value: value);

  static Future<String?> readValueSecure(LoginInfo key) async =>
      storage.read(key: key.name);

  static Future<void> deleteAllSecure() async => storage.deleteAll();
}
