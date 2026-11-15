// /api/predictions — US-22 (bonus) : probabilité de panne par machine
const router = require('express').Router();
const { z, idParam } = require('../../utils/schemas');
const service = require('../../services/prediction.service');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const AppError = require('../../utils/AppError');
const h = require('../../utils/asyncHandler');

const tous = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE, ROLES.TECHNICIEN);

router.get('/', tous, h(async (req, res) => res.json(await service.derniere())));
router.get('/modele', tous, h(async (req, res) => {
  try { res.json(await service.carteModele()); } catch (e) { throw new AppError(503, `Service d'IA indisponible : ${e.message}`, 'IA_INDISPONIBLE'); }
}));
router.get('/machines/:id', tous, validate({ params: idParam, query: z.object({ heures: z.coerce.number().int().min(1).max(720).default(48) }) }),
  h(async (req, res) => res.json(await service.historique(req.params.id, req.query.heures))));
// Calcul immédiat (démonstration) : responsable
router.post('/executer', authorize(ROLES.RESPONSABLE), h(async (req, res) => res.json(await service.executer())));

module.exports = router;
