const repo = require('./of.repository');
const AppError = require('../../utils/AppError');

module.exports = {
  list: (f) => repo.list(f),

  async get(id) {
    const of = await repo.findById(id);
    if (!of) throw AppError.notFound('Ordre de fabrication introuvable');
    return of;
  },

  async create(data) {
    const id = await repo.create(data);
    return repo.findById(id);
  },

  async update(id, data) {
    const current = await this.get(id);
    const produite = data.quantiteProduite ?? current.quantiteProduite;
    const rebutee = data.quantiteRebutee ?? current.quantiteRebutee;
    if (rebutee > produite) throw AppError.badRequest('La quantité rebutée ne peut pas dépasser la quantité produite');
    await repo.update(id, data);
    return repo.findById(id);
  },
};
