const service = require('./machines.service');

module.exports = {
  list: async (req, res) => res.json(await service.list(req.query)),
  get: async (req, res) => res.json(await service.get(req.params.id)),
  create: async (req, res) => res.status(201).json(await service.create(req.body, req.user)),
  update: async (req, res) => res.json(await service.update(req.params.id, req.body)),
  addCapteur: async (req, res) => res.status(201).json(await service.addCapteur(req.params.id, req.body)),
  updateCapteur: async (req, res) => res.json(await service.updateCapteur(req.params.id, req.body)),
  seuils: async (req, res) => res.json(await service.seuils(req.params.id)),
  setSeuil: async (req, res) =>
    res.json(await service.setSeuil(req.params.id, req.params.typeMesure, req.body, req.user)),
  mesures: async (req, res) => res.json(await service.mesures(req.params.id, req.query)),
  setCout: async (req, res) => res.json(await service.setCout(req.params.id, req.body)),
  declarerPanne: async (req, res) => res.status(201).json(await service.declarerPanne(req.params.id, req.body, req.user)),
  comparaison: async (req, res) => res.json(await service.comparaison(req.query)),
  calibrer: async (req, res) => res.json(await service.calibrer(req.params.id, req.body, req.user)),
  remplacerCapteur: async (req, res) => res.status(201).json(await service.remplacerCapteur(req.params.id, req.body)),
  mesuresHoraires: async (req, res) => res.json(await service.mesuresHoraires(req.params.id, req.query)),
  historique: async (req, res) => res.json(await service.historique(req.params.id, req.query)),
};
