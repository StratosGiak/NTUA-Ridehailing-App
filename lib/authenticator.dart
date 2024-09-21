import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:ntua_ridehailing/constants.dart';

class Authenticator {
  Authenticator._();
  static final Authenticator _instance = Authenticator._();

  factory Authenticator() {
    return _instance;
  }

  static const appAuth = FlutterAppAuth();
  static String? _idToken;
  static String? _accessToken;
  static String? _refreshToken;

  static String? get idToken => _idToken;
  static String? get accessToken => _accessToken;
  static String? get refreshToken => _refreshToken;

  static Future<String?> authenticate() async {
    final request = AuthorizationTokenRequest(
      authClientID,
      '$appScheme:/auth',
      issuer: authIssuer,
      scopes: ['openid', 'profile', 'email'],
      additionalParameters: {'kc_idp_hint': 'saml'},
    );
    final response = await appAuth.authorizeAndExchangeCode(request);
    _idToken = response?.idToken;
    _accessToken = response?.accessToken;
    _refreshToken = response?.refreshToken;
    return _idToken;
  }

  static Future<String?> refresh() async {
    final request = TokenRequest(
      authClientID,
      '$appScheme:/auth',
      issuer: authIssuer,
      refreshToken: _refreshToken,
      scopes: ['openid', 'profile', 'email'],
    );
    final response = await appAuth.token(request);
    _accessToken = response?.accessToken;
    _refreshToken = response?.refreshToken;
    return _accessToken;
  }

  static Future<void> endSession() async {
    final request = EndSessionRequest(
      issuer: authIssuer,
      idTokenHint: _idToken,
      postLogoutRedirectUrl: '$appScheme:/',
    );
    final response = await appAuth.endSession(request);
    if (response != null) {
      _idToken = null;
      _accessToken = null;
      _refreshToken = null;
    }
  }
}
