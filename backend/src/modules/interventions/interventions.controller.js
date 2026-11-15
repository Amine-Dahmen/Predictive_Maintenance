const service = require('./interventions.service');

module.exports = {
  list: async (req, res) => res.json(await service.list(req.query, req.user)),
  get: async (req, res) => res.json(await service.get(req.params.id, req.user)),
  create: async (req, res) => res.status(201).json(await service.create(req.body, req.user)),
  update: async (req, res) => res.json(await service.update(req.params.id, req.body)),
  affecter: async (req, res) => res.json(await service.affecter(req.params.id, req.body)),
  annuler: async (req, res) => res.json(await service.annuler(req.params.id)),
  prendreEnCharge: async (req, res) => res.json(await service.prendreEnCharge(req.params.id, req.user)),
  demarrer: async (req, res) => res.json(await service.demarrer(req.params.id, req.user)),
  getCompteRendu: async (req, res) => res.json(await service.getCompteRendu(req.params.id, req.user)),
  saveCompteRendu: async (req, res) => res.json(await service.saveCompteRendu(req.params.id, req.body, req.user)),
  listerPhotos: async (req, res) => res.json(await service.listerPhotos(req.params.id, req.user)),
  ajouterPhoto: async (req, res) => res.status(201).json(await service.ajouterPhoto(req.params.id, req.file, req.body?.legende, req.user)),
  fichierPhoto: async (req, res) => {
    const f = await service.fichierPhoto(req.params.id, req.params.photoId, req.user);
    res.set({ 'Content-Type': f.mime, 'Cache-Control': 'private, max-age=86400', 'X-Content-Type-Options': 'nosniff' });
    res.sendFile(f.chemin, (err) => { if (err && !res.headersSent) res.status(404).end(); });
  },
  supprimerPhoto: async (req, res) => { await service.supprimerPhoto(req.params.id, req.params.photoId, req.user); res.status(204).end(); },
  cloturer: async (req, res) => res.json(await service.cloturer(req.params.id, req.body, req.user)),
};
