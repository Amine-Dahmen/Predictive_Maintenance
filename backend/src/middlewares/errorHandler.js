const AppError = require('../utils/AppError');
const logger = require('../utils/logger');
const env = require('../config/env');

function notFound(req, res, next) {
  next(AppError.notFound(`Route introuvable : ${req.method} ${req.originalUrl}`));
}

// Traduit les erreurs PostgreSQL courantes en messages compréhensibles pour le front
function fromPostgres(err) {
  switch (err.code) {
    case '23505': return AppError.conflict('Cette valeur existe déjà (doublon)');
    case '23503': return AppError.badRequest('Référence vers un élément inexistant');
    case '23514': return AppError.badRequest('Valeur refusée par une règle de cohérence');
    case '22P02': return AppError.badRequest('Valeur de type invalide');
    default: return null;
  }
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  let error = err instanceof AppError ? err : fromPostgres(err);
  if (!error && err.type === 'entity.parse.failed') error = AppError.badRequest('JSON mal formé');
  if (!error) {
    logger.error(err);
    error = new AppError(500, 'Erreur interne du serveur', 'ERREUR_INTERNE');
  }
  const body = { erreur: { code: error.code, message: error.message } };
  if (error.details) body.erreur.details = error.details;
  if (!env.isProd && error.status === 500) body.erreur.trace = err.message;
  res.status(error.status).json(body);
}

module.exports = { notFound, errorHandler };
