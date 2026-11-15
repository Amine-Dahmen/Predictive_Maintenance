import 'api_client.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    required this.userName,
    required this.mustChangePassword,
  });

  final String accessToken;
  final String refreshToken;
  final String role;
  final String userName;
  final bool mustChangePassword;
}

class AuthService {
  AuthService(this.client);

  final ApiClient client;

  Future<AuthSession> login(String email, String password) async {
    final data =
        await client.request(
              'POST',
              '/auth/login',
              body: {'email': email, 'motDePasse': password},
            )
            as Map<String, dynamic>;
    final user = data['utilisateur'] as Map<String, dynamic>;
    final session = AuthSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      role: user['role'] as String,
      userName: _displayName(user),
      mustChangePassword: user['doitChangerMotDePasse'] == true,
    );
    client.accessToken = session.accessToken;
    client.refreshToken = session.refreshToken;
    return session;
  }

  String _displayName(Map<String, dynamic> user) {
    final firstName = user['prenom']?.toString().trim() ?? '';
    final lastName = user['nom']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    return fullName.isEmpty ? 'Utilisateur' : fullName;
  }
}
