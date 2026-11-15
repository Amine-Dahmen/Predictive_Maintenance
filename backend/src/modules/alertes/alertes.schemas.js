const { z, periode } = require('../../utils/schemas');

const list = periode.and(z.object({
  machineId: z.coerce.number().int().positive().optional(),
  statut: z.enum(['OUVERTE', 'PRISE_EN_COMPTE', 'CLOTUREE']).optional(),
  niveau: z.enum(['ALERTE', 'CRITIQUE']).optional(),
  fausseAlerte: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  limit: z.coerce.number().int().min(1).max(1000).default(200),
}));

const cloture = z.object({ commentaire: z.string().trim().min(3, 'Commentaire obligatoire').max(1000) });

module.exports = { list, cloture, periode };
