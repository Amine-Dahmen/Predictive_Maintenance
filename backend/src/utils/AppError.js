// Erreur métier avec code HTTP. Le middleware errorHandler la transforme en réponse JSON propre.
class AppError extends Error {
  constructor(status, message, code, details) {
    super(message);
    this.status = status;
    this.code = code || 'ERREUR';
    this.details = details;
  }

  static badRequest(msg, details) { return new AppError(400, msg, 'REQUETE_INVALIDE', details); }
  static unauthorized(msg = 'Authentification requise') { return new AppError(401, msg, 'NON_AUTHENTIFIE'); }
  static forbidden(msg = 'Accès refusé') { return new AppError(403, msg, 'ACCES_REFUSE'); }
  static notFound(msg = 'Ressource introuvable') { return new AppError(404, msg, 'INTROUVABLE'); }
  static conflict(msg) { return new AppError(409, msg, 'CONFLIT'); }
}

module.exports = AppError;
