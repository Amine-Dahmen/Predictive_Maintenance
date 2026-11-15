// /api/rapports/maintenance — US-17 (directeur et responsable)
const router = require('express').Router();
const { z, periode } = require('../../utils/schemas');
const service = require('./rapports.service');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const h = require('../../utils/asyncHandler');

const q = periode.and(z.object({
  format: z.enum(['json', 'csv', 'html']).default('json'),
  periode: z.enum(['semaine-precedente', 'mois-precedent']).optional(),
}));

router.get('/maintenance', authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE), validate({ query: q }), h(async (req, res) => {
  // req.query est validé par zod (format et période : listes fermées, dates) et le HTML est échappé
  // (rapports.service.esc, testé) : pas de donnée utilisateur brute dans la réponse.
  // nosemgrep: ajinabraham.njsscan.xss.xss_node.express_xss
  const r = await service.generer(req.query);
  const nom = `rapport-maintenance-${r.periode.from.toISOString().slice(0, 10)}`;
  if (req.query.format === 'csv') {
    res.set({ 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': `attachment; filename="${nom}.csv"` });
    return res.send(service.enCsv(r));
  }
  if (req.query.format === 'html') {
    // Page autonome sans aucun script (impression : Ctrl+P)
    res.set({ 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'" });
    return res.send(service.enHtml(r));
  }
  return res.json(r);
}));

module.exports = router;
