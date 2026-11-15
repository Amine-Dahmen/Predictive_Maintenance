// US-17 : rapport périodique de maintenance (JSON, CSV pour un tableur, HTML imprimable en PDF).
const { query } = require('../../config/db');
const indicateurs = require('../indicateurs/indicateurs.service');
const { resolvePeriode } = require('../../utils/schemas');

// Période prédéfinie : semaine ou mois précédent (complets), sinon from/to
function periodePredefinie(type, maintenant = new Date()) {
  const d = new Date(Date.UTC(maintenant.getUTCFullYear(), maintenant.getUTCMonth(), maintenant.getUTCDate()));
  if (type === 'mois-precedent') {
    const to = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
    return { from: new Date(Date.UTC(to.getUTCFullYear(), to.getUTCMonth() - 1, 1)), to };
  }
  if (type === 'semaine-precedente') {
    const lundi = new Date(d.getTime() - ((d.getUTCDay() + 6) % 7) * 86400000);
    return { from: new Date(lundi.getTime() - 7 * 86400000), to: lundi };
  }
  return null;
}

async function generer({ periode: type, ...q }) {
  const { from, to } = periodePredefinie(type) || resolvePeriode(q);
  const [ind, pannes, interventions, alertes] = await Promise.all([
    indicateurs.indicateurs({ from, to }),
    indicateurs.pannes({ from, to, grain: 'week' }),
    query(
      `SELECT i.id, i.type, i.statut, i.priorite, m.code AS machine, i.description, i.resultat,
              i.date_debut AS "dateDebut", i.date_fin AS "dateFin",
              CONCAT(t.prenom, ' ', t.nom) AS technicien,
              ROUND(EXTRACT(EPOCH FROM (i.date_fin - i.date_debut)) / 60)::int AS "dureeMin"
       FROM interventions i JOIN machines m ON m.id = i.machine_id LEFT JOIN utilisateurs t ON t.id = i.technicien_id
       WHERE i.statut = 'CLOTUREE' AND i.date_fin BETWEEN $1 AND $2 ORDER BY i.date_fin`, [from, to],
    ),
    query(
      `SELECT COUNT(*)::int AS total,
              (COUNT(*) FILTER (WHERE niveau = 'CRITIQUE' AND NOT fausse_alerte))::int AS critiques,
              (COUNT(*) FILTER (WHERE fausse_alerte))::int AS fausses,
              ROUND(AVG(EXTRACT(EPOCH FROM (prise_en_compte_at - created_at)) / 60)::numeric, 1)::float AS "delaiPriseEnCompteMin"
       FROM alertes WHERE created_at BETWEEN $1 AND $2`, [from, to],
    ),
  ]);
  return {
    titre: 'Rapport de maintenance', genereLe: new Date(), periode: { from, to },
    global: ind.global, machines: ind.machines, pannes: pannes.series,
    alertes: alertes.rows[0], interventions: interventions.rows,
  };
}

// --------- Formats ---------
const csvCell = (v) => {
  if (v === null || v === undefined) return '';
  let s = v instanceof Date ? v.toISOString() : String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`; // pas de formule exécutée à l'ouverture dans un tableur
  return /[";\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const ligne = (cells) => cells.map(csvCell).join(';');

function enCsv(r) {
  const out = [
    ligne(['Rapport de maintenance', `du ${r.periode.from.toISOString()}`, `au ${r.periode.to.toISOString()}`]), '',
    ligne(['Machine', 'Nom', 'Disponibilité (%)', 'Pannes', 'Temps d\'arrêt (h)', 'MTBF (h)', 'MTTR (h)', 'Coût des arrêts', 'TRS (%)']),
    ...r.machines.map((m) => ligne([m.code, m.nom, pct(m.disponibilite), m.nbPannes, m.tempsArretH, m.mtbfH, m.mttrH, m.coutArret, pct(m.trs)])),
    ligne(['TOTAL', '', pct(r.global.disponibilite), r.global.nbPannes, r.global.tempsArretH, r.global.mtbfH, r.global.mttrH, r.global.coutArret, pct(r.global.trs)]),
    '', ligne(['Intervention', 'Machine', 'Type', 'Technicien', 'Fin', 'Durée (min)', 'Résultat', 'Description']),
    ...r.interventions.map((i) => ligne([i.id, i.machine, i.type, i.technicien, i.dateFin, i.dureeMin, i.resultat, i.description])),
  ];
  return `﻿${out.join('\r\n')}\r\n`; // BOM : accents corrects dans Excel
}

const pct = (v) => (v === null || v === undefined ? null : Math.round(v * 1000) / 10);
const esc = (v) => String(v ?? '—').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const dateFr = (d) => (d ? new Date(d).toLocaleDateString('fr-FR') : '—');

function enHtml(r) {
  const g = r.global;
  const kpi = (label, v) => `<div class="kpi"><span>${label}</span><b>${esc(v)}</b></div>`;
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Rapport de maintenance</title>
<style>body{font:14px system-ui,sans-serif;margin:32px;color:#1d2433}h1{margin:0}small{color:#667}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:20px 0}.kpi{border:1px solid #d8dde6;border-radius:8px;padding:12px}
.kpi span{display:block;color:#667;font-size:12px}.kpi b{font-size:20px}table{width:100%;border-collapse:collapse;margin:12px 0 24px}
th,td{border-bottom:1px solid #e3e7ee;padding:6px 8px;text-align:left;font-size:13px}th{background:#f3f5f9}
@media print{body{margin:12mm}p[style]{display:none}}</style></head><body>
<p style="float:right;color:#667">Ctrl+P : imprimer ou enregistrer en PDF</p>
<h1>Rapport de maintenance</h1><small>Période du ${dateFr(r.periode.from)} au ${dateFr(r.periode.to)} · généré le ${new Date(r.genereLe).toLocaleString('fr-FR')}</small>
<div class="kpis">${kpi('Disponibilité', g.disponibilite == null ? '—' : `${pct(g.disponibilite)} %`)}${kpi('Pannes', g.nbPannes)}
${kpi('MTBF', g.mtbfH == null ? '—' : `${g.mtbfH} h`)}${kpi('MTTR', g.mttrH == null ? '—' : `${g.mttrH} h`)}
${kpi("Temps d'arrêt", `${g.tempsArretH} h`)}${kpi('Coût des arrêts', g.coutArret)}${kpi('Alertes (critiques)', `${r.alertes.total} (${r.alertes.critiques})`)}
${kpi('Fausses alertes', r.alertes.fausses)}</div>
<h2>Par machine</h2><table><tr><th>Machine</th><th>Disponibilité</th><th>Pannes</th><th>Arrêt (h)</th><th>MTBF (h)</th><th>MTTR (h)</th><th>Coût</th></tr>
${r.machines.map((m) => `<tr><td><b>${esc(m.code)}</b> ${esc(m.nom)}</td><td>${m.disponibilite == null ? '—' : `${pct(m.disponibilite)} %`}</td><td>${m.nbPannes}</td><td>${m.tempsArretH}</td><td>${esc(m.mtbfH)}</td><td>${esc(m.mttrH)}</td><td>${esc(m.coutArret)}</td></tr>`).join('')}</table>
<h2>Interventions clôturées (${r.interventions.length})</h2><table><tr><th>#</th><th>Machine</th><th>Type</th><th>Technicien</th><th>Fin</th><th>Durée</th><th>Résultat</th></tr>
${r.interventions.map((i) => `<tr><td>${i.id}</td><td>${esc(i.machine)}</td><td>${esc(i.type)}</td><td>${esc(i.technicien)}</td><td>${dateFr(i.dateFin)}</td><td>${i.dureeMin ?? '—'} min</td><td>${esc(i.resultat)}</td></tr>`).join('') || '<tr><td colspan="7">Aucune</td></tr>'}</table>
</body></html>`;
}

module.exports = { generer, enCsv, enHtml, periodePredefinie, csvCell };
