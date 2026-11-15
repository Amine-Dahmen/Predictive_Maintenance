const service = require('./auth.service');

exports.login = async (req, res) => res.json(await service.login(req.body.email, req.body.motDePasse));

exports.refresh = async (req, res) => res.json(await service.refresh(req.body.refreshToken));

exports.logout = async (req, res) => {
  await service.logout(req.body.refreshToken);
  res.status(204).end();
};

exports.me = async (req, res) => res.json(service.publicUser(req.user));

exports.updateProfile = async (req, res) =>
  res.json(await service.updateProfile(req.user.id, req.body.telephone));

exports.changePassword = async (req, res) =>
  res.json(await service.changePassword(req.user.id, req.body.ancienMotDePasse, req.body.nouveauMotDePasse));
