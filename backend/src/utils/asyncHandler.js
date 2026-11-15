// Enveloppe un contrôleur async pour transmettre les erreurs à Express sans try/catch partout.
module.exports = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
