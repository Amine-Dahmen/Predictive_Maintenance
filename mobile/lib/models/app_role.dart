enum AppRole { directeur, chefProduction, technicien }

extension AppRoleLabel on AppRole {
  static AppRole? fromBackendRole(String role) {
    switch (role) {
      case 'DIRECTEUR':
        return AppRole.directeur;
      case 'RESPONSABLE':
        return AppRole.chefProduction;
      case 'TECHNICIEN':
        return AppRole.technicien;
      default:
        return null;
    }
  }

  String get label => switch (this) {
    AppRole.directeur => 'Directeur',
    AppRole.chefProduction => 'Responsable de maintenance',
    AppRole.technicien => 'Technicien',
  };

  String get backendRole => switch (this) {
    AppRole.directeur => 'DIRECTEUR',
    AppRole.chefProduction => 'RESPONSABLE',
    AppRole.technicien => 'TECHNICIEN',
  };
}
