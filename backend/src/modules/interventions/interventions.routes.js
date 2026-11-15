// /api/interventions
const router = require('express').Router();
const c = require('./interventions.controller');
const s = require('./interventions.schemas');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const { idParam } = require('../../utils/schemas');
const h = require('../../utils/asyncHandler');
const { z } = require('../../utils/schemas');
const { recevoirPhoto } = require('./photos');

const photoParams = z.object({ id: z.coerce.number().int().positive(), photoId: z.coerce.number().int().positive() });
const terrain = authorize(ROLES.RESPONSABLE, ROLES.TECHNICIEN);

const tous = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE, ROLES.TECHNICIEN);
const responsable = authorize(ROLES.RESPONSABLE);
const technicien = authorize(ROLES.TECHNICIEN);

// Consultation (le technicien ne voit que les siennes, filtré dans le service)
router.get('/', tous, validate({ query: s.list }), h(c.list));
router.get('/:id', tous, validate({ params: idParam }), h(c.get));
router.get('/:id/compte-rendu', tous, validate({ params: idParam }), h(c.getCompteRendu));

// US-25 : photos (le technicien : uniquement sur ses interventions)
router.get('/:id/photos', tous, validate({ params: idParam }), h(c.listerPhotos));
router.post('/:id/photos', terrain, validate({ params: idParam }), recevoirPhoto, h(c.ajouterPhoto));
router.get('/:id/photos/:photoId/fichier', tous, validate({ params: photoParams }), h(c.fichierPhoto));
router.delete('/:id/photos/:photoId', terrain, validate({ params: photoParams }), h(c.supprimerPhoto));

// Responsable de maintenance : planification et affectation
router.post('/', responsable, validate({ body: s.create }), h(c.create));
router.patch('/:id', responsable, validate({ params: idParam, body: s.update }), h(c.update));
router.patch('/:id/affecter', responsable, validate({ params: idParam, body: s.affecter }), h(c.affecter));
router.patch('/:id/annuler', responsable, validate({ params: idParam }), h(c.annuler));

// Technicien : exécution
router.patch('/:id/prendre-en-charge', technicien, validate({ params: idParam }), h(c.prendreEnCharge));
router.patch('/:id/demarrer', technicien, validate({ params: idParam }), h(c.demarrer));
router.put('/:id/compte-rendu', technicien, validate({ params: idParam, body: s.compteRendu }), h(c.saveCompteRendu));
router.patch('/:id/cloturer', technicien, validate({ params: idParam, body: s.cloturer }), h(c.cloturer));

module.exports = router;
