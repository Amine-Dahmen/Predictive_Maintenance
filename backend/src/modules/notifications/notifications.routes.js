// /api/notifications/canaux — US-38 (administration : directeur)
const router = require('express').Router();
const { z } = require('../../utils/schemas');
const service = require('./notifications.service');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const h = require('../../utils/asyncHandler');

const admin = authorize(ROLES.DIRECTEUR);
const params = z.object({ canal: z.enum(['APP', 'EMAIL']) });
const body = z.object({
  actif: z.boolean().optional(),
  niveauMin: z.enum(['ALERTE', 'CRITIQUE']).optional(),
  destinataires: z.string().trim().max(1000)
    .refine((v) => !v || v.split(',').every((e) => z.string().email().safeParse(e.trim()).success), 'E-mails séparés par des virgules')
    .nullable().optional(),
}).refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');

router.get('/canaux', admin, h(async (req, res) => res.json(await service.lister())));
router.put('/canaux/:canal', admin, validate({ params, body }), h(async (req, res) =>
  res.json(await service.modifier(req.params.canal, req.body, req.user))));

module.exports = router;
