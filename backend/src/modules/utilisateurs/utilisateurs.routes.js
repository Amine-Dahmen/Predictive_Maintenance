const express = require('express');
const services = require('./utilisateurs.service');
const makeController = require('./utilisateurs.controller');
const schemas = require('./utilisateurs.schemas');
const validate = require('../../middlewares/validate');
const { authorize, ROLES } = require('../../middlewares/auth');
const { idParam } = require('../../utils/schemas');
const h = require('../../utils/asyncHandler');

// /api/responsables : gérés par le Directeur (PB-02 à PB-05)
const responsables = express.Router();
{
  const c = makeController(services.responsables);
  const admin = authorize(ROLES.DIRECTEUR);
  responsables.get('/', admin, validate({ query: schemas.list }), h(c.list));
  responsables.get('/:id', admin, validate({ params: idParam }), h(c.get));
  responsables.post('/', admin, validate({ body: schemas.createResponsable }), h(c.create));
  responsables.patch('/:id', admin, validate({ params: idParam, body: schemas.updateResponsable }), h(c.update));
  responsables.patch('/:id/statut', admin, validate({ params: idParam, body: schemas.statut }), h(c.setStatut));
  responsables.post('/:id/reinitialiser-mot-de-passe', admin, validate({ params: idParam }), h(c.reinitialiserMotDePasse)); // US-35
}

// /api/techniciens : gérés par le Responsable, consultables par le Directeur (PB-24 à PB-26)
const techniciens = express.Router();
{
  const c = makeController(services.techniciens);
  const lecture = authorize(ROLES.RESPONSABLE, ROLES.DIRECTEUR);
  const gestion = authorize(ROLES.RESPONSABLE);
  techniciens.get('/', lecture, validate({ query: schemas.list }), h(c.list));
  techniciens.get('/:id', lecture, validate({ params: idParam }), h(c.get));
  techniciens.post('/', gestion, validate({ body: schemas.createTechnicien }), h(c.create));
  techniciens.patch('/:id', gestion, validate({ params: idParam, body: schemas.updateTechnicien }), h(c.update));
  techniciens.patch('/:id/statut', gestion, validate({ params: idParam, body: schemas.statut }), h(c.setStatut));
  techniciens.post('/:id/reinitialiser-mot-de-passe', gestion, validate({ params: idParam }), h(c.reinitialiserMotDePasse)); // US-35
}

module.exports = { responsables, techniciens };
