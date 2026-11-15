// Contrôleur générique : le même code sert aux responsables et aux techniciens.
module.exports = (service) => ({
  list: async (req, res) => res.json(await service.list(req.query)),
  get: async (req, res) => res.json(await service.get(req.params.id)),
  create: async (req, res) => res.status(201).json(await service.create(req.body, req.user)),
  update: async (req, res) => res.json(await service.update(req.params.id, req.body)),
  reinitialiserMotDePasse: async (req, res) => res.json(await service.reinitialiserMotDePasse(req.params.id, req.user)),
  setStatut: async (req, res) => res.json(await service.setStatut(req.params.id, req.body.statut, req.user)),
});
