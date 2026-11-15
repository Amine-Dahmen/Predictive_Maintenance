const repo = require('./alertes.repository');
const AppError = require('../../utils/AppError');
const { resolvePeriode } = require('../../utils/schemas');
const { publish } = require('../../realtime/eventBus');
const etatMachine = require('../../services/etatMachine.service');

async function get(id) {
  const a = await repo.findById(id);
  if (!a) throw AppError.notFound('Alerte introuvable');
  return a;
}

module.exports = {
  get,
  list: (q) => repo.list({ ...q, ...resolvePeriode(q) }),
  parMachine: (q) => repo.countParMachine(resolvePeriode(q)),

  async prendreEnCompte(id, user) {
    if (!(await repo.prendreEnCompte(id, user.id))) throw AppError.conflict("L'alerte n'existe pas ou n'est plus ouverte");
    const a = await get(id);
    publish('alerte.maj', a);
    return a;
  },

  async cloturer(id, commentaire) {
    const r = await repo.cloturer(id, commentaire);
    if (!r) throw AppError.conflict("L'alerte n'existe pas ou est déjà clôturée");
    await etatMachine.mettreAJour(r.machineId);
    const a = await get(id);
    publish('alerte.maj', a);
    return a;
  },

  async fausseAlerte(id, commentaire) {
    const r = await repo.marquerFausseAlerte(id, commentaire);
    if (!r) throw AppError.conflict("L'alerte n'existe pas ou est déjà marquée comme fausse alerte");
    await etatMachine.mettreAJour(r.machineId);
    const a = await get(id);
    publish('alerte.maj', a);
    return a;
  },
};
