class Technician {
  const Technician(
    this.id,
    this.nom,
    this.prenom,
    this.email,
    this.specialty,
    this.active,
  );

  final int? id;
  final String nom;
  final String prenom;
  final String email;
  final String specialty;
  final bool active;

  String get name => '$prenom $nom';

  Technician copyWith({
    String? nom,
    String? prenom,
    String? email,
    String? specialty,
    bool? active,
  }) {
    return Technician(
      id,
      nom ?? this.nom,
      prenom ?? this.prenom,
      email ?? this.email,
      specialty ?? this.specialty,
      active ?? this.active,
    );
  }
}
