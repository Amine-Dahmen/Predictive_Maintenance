// Cycle de vie d'une intervention (PB-27 à PB-41) :
//   A_AFFECTER -> AFFECTEE -> EN_COURS -> CLOTUREE        (ou ANNULEE avant le démarrage)
const repo = require('./interventions.repository');
const alertesRepo = require('../alertes/alertes.repository');
const { withTransaction, query } = require('../../config/db');
const AppError = require('../../utils/AppError');
const { publish } = require('../../realtime/eventBus');
const etatMachine = require('../../services/etatMachine.service');
const photos = require('./photos');

const MODIFIABLES = ['A_AFFECTER', 'AFFECTEE'];

async function get(id, user) {
  const i = await repo.findById(id);
  if (!i) throw AppError.notFound('Intervention introuvable');
  // Un technicien voit les interventions qui lui sont affectées, et celles que personne n'a encore prises
  const libre = i.statut === 'A_AFFECTER' && i.technicienId === null;
  if (user.role === 'TECHNICIEN' && i.technicienId !== user.id && !libre) throw AppError.notFound('Intervention introuvable');
  return i;
}

async function getDetail(id, user) {
  const intervention = await get(id, user);
  const compteRendu = await repo.findCompteRendu(id);
  const alerte = intervention.alerteId ? await alertesRepo.findById(intervention.alerteId) : null;
  return { ...intervention, compteRendu: compteRendu || null, alerte, photos: await photos.lister(id) };
}

async function notifier(id, type = 'intervention.maj') {
  const i = await repo.findById(id);
  publish(type, i, { roles: ['RESPONSABLE', 'DIRECTEUR'], userId: i.technicienId });
  return i;
}

// Vérifie que l'utilisateur est bien le technicien affecté et que le statut permet l'action
function checkTechnicien(row, user, statutsAutorises) {
  if (!row || row.technicien_id !== user.id) throw AppError.notFound('Intervention introuvable');
  if (!statutsAutorises.includes(row.statut)) {
    throw AppError.conflict(`Action impossible : l'intervention est au statut ${row.statut}`);
  }
}

module.exports = {
  get: getDetail,

  // US-25 : get() vérifie que l'utilisateur peut voir l'intervention (le technicien : seulement les siennes)
  async listerPhotos(id, user) { await get(id, user); return photos.lister(id); },
  async ajouterPhoto(id, file, legende, user) { return photos.ajouter(await get(id, user), file, legende, user); },
  async fichierPhoto(id, photoId, user) { await get(id, user); return photos.fichier(id, photoId); },
  async supprimerPhoto(id, photoId, user) { await get(id, user); return photos.supprimer(id, photoId, user); },

  list({ aPrendre, ...filters }, user) {
    if (user.role === 'TECHNICIEN') {
      // « À prendre » : interventions sans technicien ; sinon filtre forcé sur les siennes (PB-35, PB-41)
      if (aPrendre) return repo.list({ ...filters, statut: 'A_AFFECTER', technicienId: undefined, sansTechnicien: true });
      return repo.list({ ...filters, technicienId: user.id });
    }
    return repo.list(aPrendre ? { ...filters, statut: 'A_AFFECTER', sansTechnicien: true } : filters);
  },

  // Extension demandée (13/11/2026) : le technicien prend lui-même une intervention non affectée,
  // sans attendre l'affectation par le responsable (US-14). Le responsable en est informé.
  async prendreEnCharge(id, user) {
    if (!(await repo.prendreEnCharge(id, user.id))) {
      const i = await repo.findById(id);
      if (!i) throw AppError.notFound('Intervention introuvable');
      throw AppError.conflict(i.technicienId ? 'Intervention déjà prise en charge' : `Action impossible : l'intervention est au statut ${i.statut}`);
    }
    return notifier(id, 'intervention.affectee');
  },

  async create(data, user) {
    const id = await withTransaction(async (db) => {
      const d = { ...data, creePar: user.id };
      if (d.type === 'PREDICTIVE') {
        const { rows } = await db.query('SELECT id, machine_id, statut FROM alertes WHERE id = $1 FOR UPDATE', [d.alerteId]);
        const alerte = rows[0];
        if (!alerte) throw AppError.badRequest("L'alerte d'origine n'existe pas");
        if (alerte.statut === 'CLOTUREE') throw AppError.conflict("L'alerte d'origine est déjà clôturée");
        d.machineId = alerte.machine_id;
        if (alerte.statut === 'OUVERTE') {
          await db.query(`UPDATE alertes SET statut = 'PRISE_EN_COMPTE', prise_en_compte_par = $2, prise_en_compte_at = NOW() WHERE id = $1`, [alerte.id, user.id]);
        }
      }
      if (d.type === 'CURATIVE') {
        d.priorite = d.priorite || 'URGENTE';
        d.debutPanne = d.debutPanne || new Date();
      }
      d.priorite = d.priorite || 'MOYENNE';
      const exists = await db.query('SELECT 1 FROM machines WHERE id = $1', [d.machineId]);
      if (!exists.rowCount) throw AppError.badRequest("La machine n'existe pas");
      return repo.create(d, db);
    });
    const i = await notifier(id);
    await etatMachine.mettreAJour(i.machineId);
    return i;
  },

  async update(id, data) {
    const current = await repo.findById(id);
    if (!current) throw AppError.notFound('Intervention introuvable');
    if (!MODIFIABLES.includes(current.statut)) throw AppError.conflict('Une intervention démarrée ou terminée ne peut plus être modifiée');
    await repo.update(id, data);
    const result = await notifier(id);
    const conflits = current.technicienId && data.datePrevue
      ? await repo.conflitsTechnicien(current.technicienId, data.datePrevue, id) : [];
    return { ...result, avertissements: conflits.length ? [`Le technicien a déjà ${conflits.length} intervention(s) ce jour-là`] : [] };
  },

  async affecter(id, { technicienId, echeance, priorite }) {
    const current = await repo.findById(id);
    if (!current) throw AppError.notFound('Intervention introuvable');
    if (!MODIFIABLES.includes(current.statut)) throw AppError.conflict("Cette intervention ne peut plus être affectée");
    const tech = await repo.findTechnicienActif(technicienId);
    if (!tech) throw AppError.badRequest('Technicien introuvable ou désactivé');

    await repo.update(id, { technicienId, echeance, priorite, statut: 'AFFECTEE' });
    if (current.technicienId && current.technicienId !== technicienId) {
      publish('intervention.retiree', { id }, { userId: current.technicienId });
    }
    const i = await notifier(id, 'intervention.affectee'); // notification au technicien (PB-34)
    const conflits = await repo.conflitsTechnicien(technicienId, i.datePrevue || echeance, id);
    return { ...i, avertissements: conflits.length ? [`${tech.prenom} ${tech.nom} a déjà ${conflits.length} intervention(s) ce jour-là`] : [] };
  },

  async annuler(id) {
    const current = await repo.findById(id);
    if (!current) throw AppError.notFound('Intervention introuvable');
    if (!MODIFIABLES.includes(current.statut)) throw AppError.conflict('Seule une intervention non démarrée peut être annulée');
    await repo.update(id, { statut: 'ANNULEE' });
    await etatMachine.mettreAJour(current.machineId);
    return notifier(id);
  },

  async demarrer(id, user) {
    await withTransaction(async (db) => {
      const row = await repo.lockById(id, db);
      checkTechnicien(row, user, ['AFFECTEE']);
      await repo.update(id, { statut: 'EN_COURS', dateDebut: new Date() }, db);
      await repo.setTechnicienDisponible(user.id, db);
    });
    const i = await notifier(id);
    await etatMachine.mettreAJour(i.machineId);
    return i;
  },

  async getCompteRendu(id, user) {
    await get(id, user);
    const cr = await repo.findCompteRendu(id);
    if (!cr) throw AppError.notFound('Aucun compte rendu pour cette intervention');
    return cr;
  },

  async saveCompteRendu(id, data, user) {
    const row = (await query('SELECT * FROM interventions WHERE id = $1', [id])).rows[0];
    checkTechnicien(row, user, ['EN_COURS']);
    return repo.upsertCompteRendu(id, data);
  },

  async cloturer(id, { resultat }, user) {
    const machineId = await withTransaction(async (db) => {
      const row = await repo.lockById(id, db);
      checkTechnicien(row, user, ['EN_COURS']);
      const cr = await repo.findCompteRendu(id, db);
      if (!cr || !cr.diagnostic || !cr.actions) {
        throw AppError.badRequest('Renseignez le diagnostic et les actions réalisées avant de clôturer');
      }
      await repo.update(id, { statut: 'CLOTUREE', dateFin: new Date(), resultat }, db);
      await repo.finaliserCompteRendu(id, db);
      await repo.setTechnicienDisponible(user.id, db);
      // Clôture de l'alerte d'origine, et de toutes les alertes de la machine si elle est remise en service
      if (row.alerte_id) await alertesRepo.cloturer(row.alerte_id, `Clôturée par l'intervention #${id}`, db);
      if (resultat === 'REMISE_EN_SERVICE') {
        await db.query(`UPDATE alertes SET statut = 'CLOTUREE', cloturee_at = NOW(),
                          commentaire = COALESCE(commentaire, $2)
                        WHERE machine_id = $1 AND statut <> 'CLOTUREE'`, [row.machine_id, `Machine remise en service (intervention #${id})`]);
      }
      return row.machine_id;
    });
    await etatMachine.mettreAJour(machineId);
    return notifier(id);
  },
};
