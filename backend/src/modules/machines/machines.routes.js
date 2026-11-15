const express = require('express');
const c = require('./machines.controller');
const s = require('./machines.schemas');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const { idParam } = require('../../utils/schemas');
const h = require('../../utils/asyncHandler');

const tous = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE, ROLES.TECHNICIEN);
const responsable = authorize(ROLES.RESPONSABLE);
const terrain = authorize(ROLES.RESPONSABLE, ROLES.TECHNICIEN);
const pilotage = authorize(ROLES.DIRECTEUR, ROLES.RESPONSABLE);

// /api/machines
const machines = express.Router();
machines.get('/', tous, validate({ query: s.listMachines }), h(c.list));
machines.get('/comparaison', tous, validate({ query: s.comparaison }), h(c.comparaison)); // US-32 (avant /:id)
machines.get('/:id', tous, validate({ params: idParam }), h(c.get));
machines.post('/', responsable, validate({ body: s.createMachine }), h(c.create));
machines.patch('/:id', responsable, validate({ params: idParam, body: s.updateMachine }), h(c.update));

machines.get('/:id/historique', tous, validate({ params: idParam, query: s.periode }), h(c.historique));
machines.get('/:id/mesures', tous, validate({ params: idParam, query: s.mesuresQuery }), h(c.mesures));
machines.get('/:id/mesures-horaires', tous, validate({ params: idParam, query: s.mesuresQuery }), h(c.mesuresHoraires)); // US-40
machines.patch('/:id/cout', pilotage, validate({ params: idParam, body: s.coutMachine }), h(c.setCout)); // US-34
// US-29 : déclarée par le responsable, qui affecte la réparation (US-14) ; un technicien qui constate la
// panne peut aussi la déclarer : la réparation lui est alors affectée d'office (jamais orpheline)
machines.post('/:id/pannes', terrain, validate({ params: idParam, body: s.declarerPanne }), h(c.declarerPanne));

machines.post('/:id/capteurs', responsable, validate({ params: idParam, body: s.createCapteur }), h(c.addCapteur));

machines.get('/:id/seuils', tous, validate({ params: idParam }), h(c.seuils));
machines.put('/:id/seuils/:typeMesure', responsable, validate({ params: s.seuilParams, body: s.seuilBody }), h(c.setSeuil));

// /api/capteurs
const capteurs = express.Router();
capteurs.patch('/:id', responsable, validate({ params: idParam, body: s.updateCapteur }), h(c.updateCapteur));
capteurs.patch('/:id/calibration', terrain, validate({ params: idParam, body: s.calibration }), h(c.calibrer)); // US-39
capteurs.post('/:id/remplacer', responsable, validate({ params: idParam, body: s.remplacerCapteur }), h(c.remplacerCapteur)); // US-37

module.exports = { machines, capteurs };
