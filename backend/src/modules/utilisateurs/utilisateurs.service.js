const repo = require('./utilisateurs.repository');
const { hashPassword, generateTemporaryPassword } = require('../../utils/password');
const AppError = require('../../utils/AppError');
const logger = require('../../utils/logger');
const { publish } = require('../../realtime/eventBus');

const LABEL = { RESPONSABLE: 'Responsable', TECHNICIEN: 'Technicien' };

function makeService(role) {
  return {
    list: (filters) => repo.list(role, filters),

    async get(id) {
      const u = await repo.findById(id, role);
      if (!u) throw AppError.notFound(`${LABEL[role]} introuvable`);
      return u;
    },

    // Le mot de passe provisoire est renvoyé UNE seule fois à l'administrateur qui crée le compte.
    // En production, l'envoyer plutôt par e-mail.
    async create(data, auteur) {
      const motDePasseProvisoire = generateTemporaryPassword();
      const user = await repo.create(data, role, await hashPassword(motDePasseProvisoire), auteur.id);
      logger.info(`${LABEL[role]} ${user.email} créé par l'utilisateur ${auteur.id}`);
      return { ...user, motDePasseProvisoire };
    },

    async update(id, data) {
      const u = await repo.update(id, role, data);
      if (!u) throw AppError.notFound(`${LABEL[role]} introuvable`);
      return u;
    },

    async setStatut(id, statut, auteur) {
      if (id === auteur.id) throw AppError.badRequest('Vous ne pouvez pas modifier votre propre statut');
      const u = await repo.setStatut(id, role, statut);
      if (!u) throw AppError.notFound(`${LABEL[role]} introuvable`);
      logger.info(`${LABEL[role]} ${id} passé à ${statut} par l'utilisateur ${auteur.id}`);
      // US-36 : le flux temps réel déjà ouvert par ce compte est fermé tout de suite
      if (statut === 'DESACTIVE') publish('session.revoquee', { utilisateurId: id }, { userId: id, interne: true });
      return u;
    },

    async reinitialiserMotDePasse(id, auteur) {
      if (id === auteur.id) throw AppError.badRequest('Utilisez « changer mon mot de passe » pour votre propre compte');
      const motDePasseProvisoire = generateTemporaryPassword();
      const u = await repo.reinitialiserMotDePasse(id, role, await hashPassword(motDePasseProvisoire));
      if (!u) throw AppError.notFound(`${LABEL[role]} introuvable`);
      logger.info(`Mot de passe de ${LABEL[role].toLowerCase()} ${id} réinitialisé par l'utilisateur ${auteur.id}`);
      publish('session.revoquee', { utilisateurId: id }, { userId: id, interne: true });
      return { ...u, motDePasseProvisoire };
    },
  };
}

module.exports = { responsables: makeService('RESPONSABLE'), techniciens: makeService('TECHNICIEN') };
