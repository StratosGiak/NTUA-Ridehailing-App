import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:ntua_ridehailing/constants.dart';

class Authenticator {
  Authenticator._();
  static final Authenticator _instance = Authenticator._();

  factory Authenticator() {
    return _instance;
  }

  static const appAuth = FlutterAppAuth();
  static String? idToken;

  static Future<String?> authenticate() {
    final request = AuthorizationTokenRequest(
      authClientID,
      '$appScheme:/auth',
      issuer: authIssuer,
      scopes: ['openid', 'profile', 'email'],
      additionalParameters: {'kc_idp_hint': 'saml'},
    );
    return appAuth.authorizeAndExchangeCode(request).then((response) {
      idToken = response?.idToken;
      return idToken;
    });
  }

  static Future<EndSessionResponse?> endSession() {
    final request = EndSessionRequest(
      issuer: authIssuer,
      idTokenHint: idToken,
      postLogoutRedirectUrl: '$appScheme:/',
    );
    return appAuth.endSession(request).then((response) {
      if (response != null) idToken = null;
      return response;
    });
  }
}
