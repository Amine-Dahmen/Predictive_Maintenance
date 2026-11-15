const service = require('./alertes.service');

module.exports = {
  list: async (req, res) => res.json(await service.list(req.query)),
  parMachine: async (req, res) => res.json(await service.parMachine(req.query)),
  get: async (req, res) => res.json(await service.get(req.params.id)),
  prendreEnCompte: async (req, res) => res.json(await service.prendreEnCompte(req.params.id, req.user)),
  cloturer: async (req, res) => res.json(await service.cloturer(req.params.id, req.body.commentaire)),
  fausseAlerte: async (req, res) => res.json(await service.fausseAlerte(req.params.id, req.body.commentaire)),
};
