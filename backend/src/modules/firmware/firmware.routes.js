// US-46 : routes du firmware. Le téléchargement est public (la carte n'a pas de JWT) mais exige
// un jeton de déploiement valide ; les autres routes sont réservées au responsable.
const express = require('express');
const { z, idParam } = require('../../utils/schemas');
const service = require('./firmware.service');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const h = require('../../utils/asyncHandler');

const telechargement = express.Router();
telechargement.get('/:jeton/:fichier',
  validate({ params: z.object({ jeton: z.string().max(64), fichier: z.string().regex(/^[a-z0-9_]{1,30}\.py$/) }) }),
  h(async (req, res) => {
    const chemin = await service.fichierPourJeton(req.params.jeton, req.params.fichier);
    res.set('Content-Type', 'text/plain; charset=utf-8');
    res.sendFile(chemin);
  }));

const gestion = express.Router();
const responsable = authorize(ROLES.RESPONSABLE);
gestion.get('/versions', authorize(ROLES.RESPONSABLE, ROLES.DIRECTEUR), h(async (req, res) => res.json(service.versions())));

// Montées sous /machines/:id/firmware
const parMachine = express.Router({ mergeParams: true });
parMachine.get('/', authorize(ROLES.RESPONSABLE, ROLES.DIRECTEUR), validate({ params: idParam }), h(async (req, res) =>
  res.json(await service.historique(req.params.id))));
parMachine.post('/', responsable, validate({ params: idParam, body: z.object({ version: z.string().regex(/^[0-9A-Za-z._-]{1,40}$/) }) }),
  h(async (req, res) => res.status(201).json(await service.deployer(req.params.id, req.body.version, req.user))));

module.exports = { telechargement, gestion, parMachine };
