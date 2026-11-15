// /api/indicateurs — tableaux de bord et KPI (Directeur et Responsable)
const router = require('express').Router();
const service = require('./indicateurs.service');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const { z, periode } = require('../../utils/schemas');
const h = require('../../utils/asyncHandler');

const lecture = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE);
const q = periode.and(z.object({ machineId: z.coerce.number().int().positive().optional() }));

const controller = {
  indicateurs: async (req, res) => res.json(await service.indicateurs(req.query)),
  dashboard: async (req, res) => res.json(await service.dashboard(req.query)),
  pannes: async (req, res) => res.json(await service.pannes(req.query)),
};
const qPannes = q.and(z.object({ grain: z.enum(['week', 'month']).optional() }));

router.get('/', lecture, validate({ query: q }), h(controller.indicateurs));
router.get('/dashboard', lecture, validate({ query: periode }), h(controller.dashboard));
router.get('/pannes', lecture, validate({ query: qPannes }), h(controller.pannes));

module.exports = router;
