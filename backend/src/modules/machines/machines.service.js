const repo = require('./machines.repository');
const AppError = require('../../utils/AppError');
const { resolvePeriode } = require('../../utils/schemas');
const etatMachine = require('../../services/etatMachine.service');
const { publierSeuilsSansAttendre } = require('../../mqtt/seuils.publisher');
const { withTransaction } = require('../../config/db');
const { publish } = require('../../realtime/eventBus');
const interventions = require('../interventions/interventions.service');
const indicateurs = require('../indicateurs/indicateurs.service');
const { TYPES_MESURE, UNITES_PAR_DEFAUT, SEUILS_PAR_DEFAUT } = require('../../utils/mesures');

async function mustExist(id) {
  const m = await repo.findById(id);
  if (!m) throw AppError.notFound('Machine introuvable');
  return m;
}

// valeur brute = (valeur enregistrée - ancien offset) / ancien gain ; on choisit l'offset pour que
// nouveau gain x valeur brute + offset = valeur de référence
function calculerOffset(derniere, ancienGain, ancienOffset, nouveauGain, reference) {
  const brute = (derniere - ancienOffset) / ancienGain;
  return Math.round((reference - nouveauGain * brute) * 1e6) / 1e6;
}

module.exports = {
  calculerOffset,
  list: (filters) => repo.list(filters),

  async get(id) {
    const machine = await mustExist(id);
    const [capteurs, seuils] = await Promise.all([repo.capteursWithLastValue(id), repo.seuils(id)]);
    return { ...machine, capteurs, seuils };
  },

  // Avec kitPredimaint, la machine est créée prête à recevoir les mesures de la carte ESP32 :
  // capteurs <code>-COURANT, -VIBRATION, -TEMPERATURE, -HUMIDITE et seuils par défaut (US-23).
  async create({ kitPredimaint, ...data }, user) {
    if (!kitPredimaint) return repo.create(data);
    const id = await withTransaction(async (db) => {
      const machine = await repo.create(data, db);
      for (const type of TYPES_MESURE) {
        await repo.createCapteur(machine.id, { identifiant: `${machine.code}-${type}`, type, unite: UNITES_PAR_DEFAUT[type] }, db);
        const [seuilAlerte, seuilCritique] = SEUILS_PAR_DEFAUT[type];
        await repo.upsertSeuil(machine.id, type, { seuilAlerte, seuilCritique }, user ? user.id : null, db);
      }
      return machine.id;
    });
    publierSeuilsSansAttendre(id);
    return this.get(id);
  },

  async update(id, data) {
    const m = await repo.update(id, data);
    if (!m) throw AppError.notFound('Machine introuvable');
    return m;
  },

  async addCapteur(machineId, data) {
    await mustExist(machineId);
    const capteur = await repo.createCapteur(machineId, { ...data, unite: data.unite || UNITES_PAR_DEFAUT[data.type] });
    return capteur;
  },

  async updateCapteur(id, data) {
    const c = await repo.updateCapteur(id, data);
    if (!c) throw AppError.notFound('Capteur introuvable');
    await etatMachine.mettreAJour(c.machineId);
    return c;
  },

  // US-34
  async setCout(id, { coutHoraireArret }) {
    return this.update(id, { coutHoraireArret });
  },

  // US-29 : une panne déclarée à la main est une intervention curative (machine en PANNE, compte dans le MTBF/MTTR)
  // La panne prend fin quand le technicien clôture cette réparation avec « remise en service ».
  async declarerPanne(machineId, { description, debutPanne, priorite, technicienId, echeance }, user) {
    await mustExist(machineId);
    const i = await interventions.create({
      type: 'CURATIVE', machineId, description: `Panne déclarée : ${description}`,
      debutPanne: debutPanne || new Date(), priorite: priorite || 'URGENTE',
    }, user);
    if (user.role === 'TECHNICIEN') {
      return interventions.affecter(i.id, {
        technicienId: user.id, echeance: echeance || new Date(Date.now() + 4 * 3600e3), priorite: priorite || 'URGENTE',
      });
    }
    if (!technicienId) return i;
    return interventions.affecter(i.id, { technicienId, echeance, priorite: priorite || 'URGENTE' });
  },

  // US-32 : comparaison de plusieurs machines sur une période
  async comparaison({ ids, type, ...q }) {
    const periode = resolvePeriode(q);
    const machines = await Promise.all(ids.map((id) => repo.findById(id)));
    const inconnues = ids.filter((id, i) => !machines[i]);
    if (inconnues.length) throw AppError.notFound(`Machine(s) introuvable(s) : ${inconnues.join(', ')}`);
    const [data, kpi] = await Promise.all([
      repo.comparaison(ids, { ...periode, type }),
      indicateurs.indicateurs({ ...periode }),
    ]);
    return {
      periode, type: type ?? null, pasS: data.pasS,
      machines: machines.map((m) => {
        const k = kpi.machines.find((x) => x.machineId === m.id) || {};
        const a = data.alertes.find((x) => x.machineId === m.id) || { nb: 0, critiques: 0 };
        return {
          id: m.id, code: m.code, nom: m.nom, etat: m.etat,
          mesures: data.stats.filter((x) => x.machineId === m.id).map(({ machineId, ...st }) => st),
          serie: data.series.filter((x) => x.machineId === m.id).map((x) => ({ t: x.t, v: x.v })),
          alertes: { total: a.nb, critiques: a.critiques },
          indicateurs: { disponibilite: k.disponibilite ?? null, nbPannes: k.nbPannes ?? 0, mtbfH: k.mtbfH ?? null,
            mttrH: k.mttrH ?? null, tempsArretH: k.tempsArretH ?? 0, coutArret: k.coutArret ?? 0 },
        };
      }),
    };
  },

  // US-39 : calibration. Les mesures déjà enregistrées ne sont pas modifiées.
  async calibrer(capteurId, { gain, offset, valeurReference }, user) {
    const c = await repo.findCapteur(capteurId);
    if (!c) throw AppError.notFound('Capteur introuvable');
    if (!c.actif) throw AppError.conflict('Ce capteur est retiré : il ne peut plus être calibré');
    const nouveauGain = gain ?? c.calibrationGain;
    let nouvelOffset = offset ?? c.calibrationOffset;
    if (valeurReference !== undefined) {
      const derniere = await repo.derniereValeur(capteurId);
      if (derniere === undefined) throw AppError.conflict('Aucune mesure reçue : impossible de calibrer sur la valeur actuelle');
      nouvelOffset = calculerOffset(derniere, c.calibrationGain, c.calibrationOffset, nouveauGain, valeurReference);
    }
    const r = await repo.setCalibration(capteurId, { gain: nouveauGain, offset: nouvelOffset }, user.id);
    publish('capteur.calibre', r, { roles: ['RESPONSABLE', 'TECHNICIEN'] });
    return r;
  },

  // US-37 : remplacement d'un capteur défectueux
  async remplacerCapteur(capteurId, { identifiant }) {
    const nouveau = await withTransaction(async (db) => {
      const { rows: [verrou] } = await db.query('SELECT id FROM capteurs WHERE id = $1 FOR UPDATE', [capteurId]);
      if (!verrou) throw AppError.notFound('Capteur introuvable');
      const ancien = await repo.findCapteur(capteurId, db);
      if (!ancien.actif) throw AppError.conflict('Ce capteur est déjà retiré');
      let id = identifiant;
      if (!id) {
        const base = ancien.identifiant.replace(/-R\d+$/, '');
        for (let n = 2; !id || (await repo.identifiantExiste(id, db)); n++) id = `${base}-R${n}`;
      }
      return repo.remplacerCapteur(ancien, id, db);
    });
    await etatMachine.mettreAJour(nouveau.machineId);
    publish('capteur.remplace', { ancienId: capteurId, nouveau }, { roles: ['RESPONSABLE', 'DIRECTEUR', 'TECHNICIEN'] });
    return nouveau;
  },

  async mesuresHoraires(machineId, q) {
    await mustExist(machineId);
    return repo.mesuresHoraires(machineId, { ...q, ...resolvePeriode(q) });
  },

  async seuils(machineId) {
    await mustExist(machineId);
    return repo.seuils(machineId);
  },

  async setSeuil(machineId, typeMesure, data, user) {
    await mustExist(machineId);
    const seuil = await repo.upsertSeuil(machineId, typeMesure, data, user.id);
    publierSeuilsSansAttendre(machineId); // la LED de la carte suit les nouveaux seuils (US-11)
    return seuil;
  },

  async mesures(machineId, q) {
    await mustExist(machineId);
    return repo.mesures(machineId, { ...q, ...resolvePeriode(q) });
  },

  async historique(machineId, q) {
    await mustExist(machineId);
    return repo.historique(machineId, resolvePeriode(q));
  },
};
