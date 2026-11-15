const { query } = require('../../config/db');

// Données brutes par machine sur la période [from, to] :
//  - pannes = interventions CURATIVE non annulées ; durée d'arrêt = début de panne -> clôture (ou maintenant)
//  - production = ordres de fabrication qui chevauchent la période
async function donneesParMachine(from, to, machineId) {
  const { rows } = await query(
    `WITH pannes AS (
       SELECT i.machine_id, i.statut, i.date_fin,
              COALESCE(i.debut_panne, i.created_at) AS debut,
              GREATEST(COALESCE(i.debut_panne, i.created_at), $1) AS s,
              LEAST(COALESCE(i.date_fin, NOW()), $2) AS e
       FROM interventions i
       WHERE i.type = 'CURATIVE' AND i.statut <> 'ANNULEE'
         AND COALESCE(i.debut_panne, i.created_at) < $2
         AND COALESCE(i.date_fin, NOW()) > $1
     ),
     arrets AS (
       SELECT machine_id,
              COALESCE(SUM(EXTRACT(EPOCH FROM (e - s))) FILTER (WHERE e > s), 0) AS arret_s,
              COUNT(*) FILTER (WHERE debut >= $1) AS nb_pannes,
              AVG(EXTRACT(EPOCH FROM (date_fin - debut))) FILTER (WHERE statut = 'CLOTUREE' AND date_fin BETWEEN $1 AND $2) AS mttr_s,
              COUNT(*) FILTER (WHERE statut = 'CLOTUREE' AND date_fin BETWEEN $1 AND $2) AS nb_reparations
       FROM pannes GROUP BY machine_id
     ),
     production AS (
       SELECT machine_id,
              SUM(quantite_produite) AS produite,
              SUM(quantite_rebutee) AS rebutee,
              SUM(quantite_produite * temps_cycle_s) AS temps_theorique_s,
              COUNT(*) FILTER (WHERE temps_cycle_s IS NULL AND quantite_produite > 0) AS of_incomplets,
              COUNT(*) FILTER (WHERE statut = 'TERMINE') AS of_termines
       FROM ordres_fabrication
       WHERE COALESCE(date_debut, created_at) < $2 AND COALESCE(date_fin, NOW()) > $1
       GROUP BY machine_id
     )
     SELECT m.id AS machine_id, m.code, m.nom, m.cout_horaire_arret::float AS cout_horaire,
            COALESCE(a.arret_s, 0)::float AS arret_s, COALESCE(a.nb_pannes, 0)::int AS nb_pannes,
            a.mttr_s::float AS mttr_s, COALESCE(a.nb_reparations, 0)::int AS nb_reparations,
            COALESCE(p.produite, 0)::int AS produite, COALESCE(p.rebutee, 0)::int AS rebutee,
            p.temps_theorique_s::float AS temps_theorique_s, COALESCE(p.of_incomplets, 0)::int AS of_incomplets,
            COALESCE(p.of_termines, 0)::int AS of_termines
     FROM machines m
     LEFT JOIN arrets a ON a.machine_id = m.id
     LEFT JOIN production p ON p.machine_id = m.id
     WHERE ($3::int IS NULL OR m.id = $3)
     ORDER BY m.code`,
    [from, to, machineId ?? null],
  );
  return rows;
}

async function compteurs() {
  const { rows } = await query(
    `SELECT
       (SELECT json_object_agg(etat, n) FROM (SELECT etat, COUNT(*)::int n FROM machines GROUP BY etat) x) AS machines_par_etat,
       (SELECT COUNT(*)::int FROM machines) AS machines_total,
       (SELECT COUNT(*)::int FROM alertes WHERE statut <> 'CLOTUREE') AS alertes_ouvertes,
       (SELECT COUNT(*)::int FROM alertes WHERE statut <> 'CLOTUREE' AND niveau = 'CRITIQUE') AS alertes_critiques,
       (SELECT json_object_agg(statut, n) FROM (SELECT statut, COUNT(*)::int n FROM interventions GROUP BY statut) y) AS interventions_par_statut,
       (SELECT COUNT(*)::int FROM interventions WHERE statut NOT IN ('CLOTUREE','ANNULEE') AND echeance < NOW()) AS interventions_en_retard,
       (SELECT COUNT(*)::int FROM ordres_fabrication WHERE statut = 'EN_COURS') AS of_en_cours`,
  );
  return rows[0];
}

// US-16 : nombre et durée des pannes par semaine ou par mois (une panne est comptée dans la période où elle commence)
async function pannesParPeriode(from, to, grain, machineId) {
  const { rows } = await query(
    `SELECT date_trunc($3, COALESCE(i.debut_panne, i.created_at)) AS periode,
            COUNT(*)::int AS nb_pannes,
            COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(i.date_fin, LEAST(NOW(), $2)) - COALESCE(i.debut_panne, i.created_at)))), 0)::float AS arret_s,
            AVG(EXTRACT(EPOCH FROM (i.date_fin - COALESCE(i.debut_panne, i.created_at)))) FILTER (WHERE i.statut = 'CLOTUREE')::float AS duree_moy_s,
            COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(i.date_fin, LEAST(NOW(), $2)) - COALESCE(i.debut_panne, i.created_at))) / 3600 * m.cout_horaire_arret), 0)::float AS cout
     FROM interventions i JOIN machines m ON m.id = i.machine_id
     WHERE i.type = 'CURATIVE' AND i.statut <> 'ANNULEE'
       AND COALESCE(i.debut_panne, i.created_at) BETWEEN $1 AND $2
       AND ($4::int IS NULL OR i.machine_id = $4)
     GROUP BY 1 ORDER BY 1`,
    [from, to, grain, machineId ?? null],
  );
  return rows;
}

module.exports = { donneesParMachine, compteurs, pannesParPeriode };
