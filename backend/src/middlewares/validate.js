// Validation des entrées avec zod. Les données validées remplacent req.body / req.query / req.params,
// donc les champs inconnus sont supprimés avant d'arriver au service (protection contre l'injection de champs).
const AppError = require('../utils/AppError');

module.exports = (schemas) => (req, res, next) => {
  for (const part of ['params', 'query', 'body']) {
    if (!schemas[part]) continue;
    const result = schemas[part].safeParse(req[part] ?? {});
    if (!result.success) {
      const details = result.error.issues.map((i) => ({ champ: i.path.join('.'), message: i.message }));
      return next(AppError.badRequest('Données invalides', details));
    }
    // req.query est en lecture seule dans certaines versions d'Express : on le redéfinit proprement
    Object.defineProperty(req, part, { value: result.data, writable: true, configurable: true, enumerable: true });
  }
  next();
};
