// Calcul des indicateurs de maintenance et de production (PB-09, PB-42 à PB-47)
//   MTBF = temps de fonctionnement / nombre de pannes
//   MTTR = durée moyenne des réparations curatives clôturées (début de panne -> clôture)
//   Disponibilité = (temps requis - temps d'arrêt) / temps requis
//   TRS = disponibilité x performance x qualité
//     performance = (pièces produites x temps de cycle théorique) / temps de fonctionnement
//     qualité     = (pièces produites - pièces rebutées) / pièces produites
// Hypothèse : le temps requis est la durée totale de la période (fonctionnement 24 h/24).
//   Coût des arrêts (US-34) = temps d'arrêt (h) x coût horaire d'arrêt de la machine
const repo = require('./indicateurs.repository');
const { resolvePeriode } = require('../../utils/schemas');

const round = (v, d = 2) => (v === null || v === undefined || Number.isNaN(v) ? null : Math.round(v * 10 ** d) / 10 ** d);

function calculer(r, periodeS) {
  const fonctionnementS = Math.max(periodeS - r.arret_s, 0);
  const disponibilite = periodeS > 0 ? fonctionnementS / periodeS : null;

  let performance = null; let qualite = null;
  if (r.produite > 0) {
    qualite = (r.produite - r.rebutee) / r.produite;
    if (r.temps_theorique_s && r.of_incomplets === 0 && fonctionnementS > 0) {
      performance = Math.min(r.temps_theorique_s / fonctionnementS, 1);
    }
  }
  const trs = disponibilite !== null && performance !== null && qualite !== null ? disponibilite * performance * qualite : null;

  return {
    tempsArretH: round(r.arret_s / 3600),
    coutArret: r.cout_horaire !== undefined ? round((r.arret_s / 3600) * (r.cout_horaire || 0)) : undefined,
    nbPannes: r.nb_pannes,
    // US-16 : fréquence ramenée à 30 jours et durée moyenne d'un arrêt
    frequencePannes30j: periodeS > 0 ? round((r.nb_pannes * 30 * 86400) / periodeS) : null,
    dureeMoyennePanneH: r.nb_pannes > 0 ? round(r.arret_s / r.nb_pannes / 3600) : null,
    mtbfH: r.nb_pannes > 0 ? round(fonctionnementS / r.nb_pannes / 3600) : null,
    mttrH: r.nb_reparations > 0 ? round(r.mttr_s / 3600) : null,
    nbReparations: r.nb_reparations,
    disponibilite: round(disponibilite, 4),
    performance: round(performance, 4),
    qualite: round(qualite, 4),
    trs: round(trs, 4),
    trsIncomplet: trs === null, // le front affiche « TRS incomplet » (PB-45)
    messages: [
      ...(r.nb_pannes === 0 ? ['Aucune panne sur la période : MTBF non calculable'] : []),
      ...(r.nb_reparations === 0 ? ['Données insuffisantes pour le MTTR'] : []),
      ...(trs === null ? ['TRS incomplet : quantités ou temps de cycle manquants'] : []),
    ],
    production: { produite: r.produite, rebutee: r.rebutee, ofTermines: r.of_termines },
  };
}

async function indicateurs({ machineId, ...q }) {
  const { from, to: toDemande } = resolvePeriode(q);
  const to = new Date(Math.min(toDemande.getTime(), Date.now())); // on ne compte pas le futur
  const periodeS = Math.max((to - from) / 1000, 0);
  const rows = await repo.donneesParMachine(from, to, machineId);

  const machines = rows.map((r) => ({ machineId: r.machine_id, code: r.code, nom: r.nom, ...calculer(r, periodeS) }));

  // Agrégat global : sommes des temps et des quantités sur toutes les machines
  const total = rows.reduce((acc, r) => ({
    arret_s: acc.arret_s + r.arret_s,
    nb_pannes: acc.nb_pannes + r.nb_pannes,
    mttr_sum: acc.mttr_sum + (r.mttr_s || 0) * r.nb_reparations,
    nb_reparations: acc.nb_reparations + r.nb_reparations,
    produite: acc.produite + r.produite,
    rebutee: acc.rebutee + r.rebutee,
    temps_theorique_s: acc.temps_theorique_s + (r.temps_theorique_s || 0),
    of_incomplets: acc.of_incomplets + r.of_incomplets,
    of_termines: acc.of_termines + r.of_termines,
  }), { arret_s: 0, nb_pannes: 0, mttr_sum: 0, nb_reparations: 0, produite: 0, rebutee: 0, temps_theorique_s: 0, of_incomplets: 0, of_termines: 0 });

  // Le parc est vu comme un tout : temps requis = durée de la période x nombre de machines
  const global = calculer({
    ...total,
    mttr_s: total.nb_reparations ? total.mttr_sum / total.nb_reparations : null,
  }, periodeS * rows.length);
  // Coût global = somme des coûts par machine (chaque machine a son coût horaire)
  global.coutArret = round(machines.reduce((acc, m) => acc + (m.coutArret || 0), 0));
  // La fréquence globale reste par machine (le temps requis du parc est multiplié par le nombre de machines)

  return { periode: { from, to }, filtres: { machineId: machineId ?? null }, global, machines };
}

// US-16 : évolution du nombre, de la durée et du coût des pannes
async function pannes({ machineId, grain = 'month', ...q }) {
  const { from, to } = resolvePeriode(q);
  const rows = await repo.pannesParPeriode(from, to, grain, machineId);
  return {
    periode: { from, to }, grain,
    series: rows.map((r) => ({
      periode: r.periode, nbPannes: r.nb_pannes, tempsArretH: round(r.arret_s / 3600),
      dureeMoyenneH: round(r.duree_moy_s / 3600), coutArret: round(r.cout),
    })),
  };
}

async function dashboard(q) {
  const [c, ind] = await Promise.all([repo.compteurs(), indicateurs(q)]);
  const parEtat = c.machines_par_etat || {};
  return {
    machines: {
      total: c.machines_total,
      parEtat,
      disponibles: (parEtat.NORMAL || 0) + (parEtat.ALERTE || 0),
    },
    alertes: { ouvertes: c.alertes_ouvertes, critiques: c.alertes_critiques },
    interventions: { parStatut: c.interventions_par_statut || {}, enRetard: c.interventions_en_retard },
    production: { ofEnCours: c.of_en_cours },
    indicateurs: ind.global,
    // US-33 : machines les plus pénalisantes sur la période
    topArrets: [...ind.machines].filter((m) => m.tempsArretH > 0)
      .sort((a, b) => b.tempsArretH - a.tempsArretH).slice(0, 5)
      .map((m) => ({ machineId: m.machineId, code: m.code, nom: m.nom, tempsArretH: m.tempsArretH, nbPannes: m.nbPannes, coutArret: m.coutArret })),
    periode: ind.periode,
  };
}

module.exports = { indicateurs, dashboard, pannes, calculer };
