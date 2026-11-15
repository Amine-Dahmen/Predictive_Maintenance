const { z } = require('../../utils/schemas');

const STATUTS = ['PLANIFIE', 'EN_COURS', 'TERMINE'];
const qte = z.number().int().min(0);

const create = z.object({
  numero: z.string().trim().min(1).max(40),
  machineId: z.number().int().positive(),
  produit: z.string().trim().min(1).max(120),
  quantitePrevue: qte,
  tempsCycleS: z.number().positive().optional(),
  dateDebut: z.coerce.date().optional(),
  dateFin: z.coerce.date().optional(),
});

const update = z.object({
  produit: z.string().trim().min(1).max(120),
  quantitePrevue: qte,
  quantiteProduite: qte,
  quantiteRebutee: qte,
  tempsCycleS: z.number().positive(),
  dateDebut: z.coerce.date(),
  dateFin: z.coerce.date(),
  statut: z.enum(STATUTS),
}).partial().refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');

const list = z.object({
  statut: z.enum(STATUTS).optional(),
  machineId: z.coerce.number().int().positive().optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
});

module.exports = { create, update, list };
