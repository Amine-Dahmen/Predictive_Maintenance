import '../models/technician.dart';
import 'api_client.dart';

class TechniciansService {
  TechniciansService(this.client);

  final ApiClient client;

  Future<List<Technician>> list() async {
    final data = await client.request('GET', '/techniciens') as List<dynamic>;
    return data.map((item) {
      final json = item as Map<String, dynamic>;
      return Technician(
        (json['id'] as num).toInt(),
        json['nom'] as String,
        json['prenom'] as String,
        json['email'] as String,
        json['specialite'] as String? ?? '',
        json['statut'] == 'ACTIF',
      );
    }).toList();
  }

  Future<String> create(Technician technician) async {
    final result = await client.request(
      'POST',
      '/techniciens',
      body: {
        'nom': technician.nom,
        'prenom': technician.prenom,
        'email': technician.email,
        'specialite': technician.specialty,
      },
    );
    if (result is! Map<String, dynamic> ||
        result['motDePasseProvisoire'] is! String) {
      throw const ApiException(
        'Le compte a été créé sans mot de passe provisoire dans la réponse API.',
      );
    }
    return result['motDePasseProvisoire'] as String;
  }

  Future<void> update(int id, Technician technician) async {
    await client.request(
      'PATCH',
      '/techniciens/$id',
      body: {
        'nom': technician.nom,
        'prenom': technician.prenom,
        'email': technician.email,
        'specialite': technician.specialty,
      },
    );
  }

  Future<void> setStatus(int id, bool active) async {
    await client.request(
      'PATCH',
      '/techniciens/$id/statut',
      body: {'statut': active ? 'ACTIF' : 'DESACTIVE'},
    );
  }

  // US-35 : nouveau mot de passe provisoire (affiché une seule fois), sessions du technicien fermées
  Future<String> resetPassword(int id) async {
    final result =
        await client.request(
              'POST',
              '/techniciens/$id/reinitialiser-mot-de-passe',
            )
            as Map<String, dynamic>;
    return result['motDePasseProvisoire'] as String;
  }
}
