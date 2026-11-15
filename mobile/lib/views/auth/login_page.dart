import 'package:flutter/material.dart';

import '../../models/app_role.dart';
import '../../viewmodels/login_view_model.dart';
import '../home/role_home_page.dart';
import 'change_password_page.dart';
import 'server_settings.dart';
import 'widgets/predictive_maintenance_hero.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final viewModel = LoginViewModel();
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  Future<void> _openApp() async {
    final session = await viewModel.login();
    if (!mounted || session == null) return;
    final role = AppRoleLabel.fromBackendRole(session.role);
    if (role == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ce rôle utilisateur n’est pas pris en charge.'),
        ),
      );
      return;
    }
    final destination = session.mustChangePassword
        ? ChangePasswordPage(
            role: role,
            apiClient: viewModel.apiClient,
            userName: session.userName,
          )
        : RoleHomePage(
            role: role,
            apiClient: viewModel.apiClient,
            userName: session.userName,
          );
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => GestureDetector(
        onTap: FocusScope.of(context).unfocus,
        behavior: HitTestBehavior.opaque,
        child: Scaffold(
          backgroundColor: const Color(0xFFF7FAFC),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keyboardIsOpen =
                    MediaQuery.viewInsetsOf(context).bottom > 0;
                final heroHeight = keyboardIsOpen
                    ? 94.0
                    : (constraints.maxWidth * 0.42)
                          .clamp(154.0, 198.0)
                          .toDouble();
                final content = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PredictiveMaintenanceHero(height: heroHeight),
                      const SizedBox(height: 20),
                      Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(color: colors.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Connexion',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: const Color(0xFF142B45),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Accédez à votre espace',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: const Color(0xFF66809D)),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: viewModel.emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Adresse e-mail',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  filled: true,
                                  fillColor: Color(0xFFF3F7FB),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: viewModel.passwordController,
                                obscureText: !_isPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!viewModel.isLoading) _openApp();
                                },
                                decoration: InputDecoration(
                                  labelText: 'Mot de passe',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  filled: true,
                                  fillColor: Color(0xFFF3F7FB),
                                  border: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(18),
                                    ),
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _isPasswordVisible
                                        ? 'Masquer le mot de passe'
                                        : 'Afficher le mot de passe',
                                    onPressed: () => setState(
                                      () => _isPasswordVisible =
                                          !_isPasswordVisible,
                                    ),
                                    icon: Icon(
                                      _isPasswordVisible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              if (viewModel.errorMessage != null) ...[
                                const SizedBox(height: 14),
                                Text(
                                  viewModel.errorMessage!,
                                  style: TextStyle(color: colors.error),
                                ),
                              ],
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 52,
                                child: FilledButton.icon(
                                  onPressed: viewModel.isLoading
                                      ? null
                                      : _openApp,
                                  icon: viewModel.isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login_rounded),
                                  label: Text(
                                    viewModel.isLoading
                                        ? 'Connexion...'
                                        : 'Se connecter',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextButton(
                                // US-35 : la réinitialisation est faite par l'administrateur du compte
                                onPressed: () =>
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Demandez à votre responsable (ou au directeur) de réinitialiser '
                                          'votre mot de passe : vous recevrez un mot de passe provisoire.',
                                        ),
                                      ),
                                    ),
                                child: const Text('Mot de passe oublié ?'),
                              ),
                              const ServerAddressTile(),
                            ],
                          ),
                        ),
                      ),
                      if (!keyboardIsOpen) ...[
                        const SizedBox(height: 24),
                        const _LoginBenefits(),
                        const SizedBox(height: 18),
                        Text(
                          'Industrie 4.0  •  IoT  •  Performance',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.4,
                            color: colors.onSurfaceVariant.withAlpha(170),
                          ),
                        ),
                      ],
                    ],
                  ),
                );

                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    keyboardIsOpen ? 16 : 20,
                    20,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: keyboardIsOpen
                      ? content
                      : ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 44,
                          ),
                          child: Center(child: content),
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginBenefits extends StatelessWidget {
  const _LoginBenefits();

  @override
  Widget build(BuildContext context) {
    const benefits = [
      (Icons.factory_outlined, 'Production\nsécurisée'),
      (Icons.schedule_outlined, 'Moins d’arrêts\nnon planifiés'),
      (Icons.insights_outlined, 'Données\nen temps réel'),
      (Icons.shield_outlined, 'Maintenance\nplus efficace'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: benefits
          .map(
            (benefit) => Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2F7F5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      benefit.$1,
                      color: const Color(0xFF087F7A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    benefit.$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF29435F),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
