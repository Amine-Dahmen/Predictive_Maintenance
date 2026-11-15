// US-17 : génère le rapport du mois (ou de la semaine) précédent dans un fichier. À planifier avec cron :
//   0 6 1 * * cd /chemin/backend && node scripts/rapport.js mois-precedent html
// Usage : node scripts/rapport.js [mois-precedent|semaine-precedente] [html|csv|json] [dossier]
const fs = require('fs');
const path = require('path');
const { pool } = require('../src/config/db');
const service = require('../src/modules/rapports/rapports.service');

const [periode = 'mois-precedent', format = 'html', dossier = 'rapports'] = process.argv.slice(2);
(async () => {
  const r = await service.generer({ periode });
  const contenu = format === 'csv' ? service.enCsv(r) : format === 'json' ? JSON.stringify(r, null, 2) : service.enHtml(r);
  fs.mkdirSync(dossier, { recursive: true });
  const fichier = path.join(dossier, `rapport-maintenance-${r.periode.from.toISOString().slice(0, 10)}.${format}`);
  fs.writeFileSync(fichier, contenu);
  console.log(`Rapport écrit : ${fichier}`);
})().catch((e) => { console.error(e.message); process.exitCode = 1; }).finally(() => pool.end());
