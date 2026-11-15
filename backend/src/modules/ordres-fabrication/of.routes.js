// /api/ordres-fabrication (PB-06) — le Directeur gère les OF, le Responsable les consulte
const router = require('express').Router();
const c = require('./of.controller');
const s = require('./of.schemas');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const { idParam } = require('../../utils/schemas');
const h = require('../../utils/asyncHandler');

const lecture = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE);
const directeur = authorize(ROLES.DIRECTEUR);

router.get('/', lecture, validate({ query: s.list }), h(c.list));
router.get('/:id', lecture, validate({ params: idParam }), h(c.get));
router.post('/', directeur, validate({ body: s.create }), h(c.create));
router.patch('/:id', directeur, validate({ params: idParam, body: s.update }), h(c.update));

module.exports = router;
