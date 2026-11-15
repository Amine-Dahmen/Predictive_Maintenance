// /api/alertes (PB-21 à PB-23). Les alertes sont créées automatiquement par le traitement MQTT.
const router = require('express').Router();
const c = require('./alertes.controller');
const s = require('./alertes.schemas');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const { idParam } = require('../../utils/schemas');
const h = require('../../utils/asyncHandler');

const lecture = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE, ROLES.TECHNICIEN);
const responsable = authorize(ROLES.RESPONSABLE);

router.get('/', lecture, validate({ query: s.list }), h(c.list));
router.get('/par-machine', lecture, validate({ query: s.periode }), h(c.parMachine));
router.get('/:id', lecture, validate({ params: idParam }), h(c.get));
// US-03 : le technicien qui reçoit l'alerte peut en accuser réception
router.patch('/:id/prise-en-compte', authorize(ROLES.RESPONSABLE, ROLES.TECHNICIEN), validate({ params: idParam }), h(c.prendreEnCompte));
router.patch('/:id/cloture', responsable, validate({ params: idParam, body: s.cloture }), h(c.cloturer));
// US-31 : marquage d'une fausse alerte (y compris une alerte déjà clôturée)
router.patch('/:id/fausse-alerte', responsable, validate({ params: idParam, body: s.cloture }), h(c.fausseAlerte));

module.exports = router;
