const { z } = require('../../utils/schemas');

const base = {
  nom: z.string().trim().min(1).max(80),
  prenom: z.string().trim().min(1).max(80),
  email: z.string().trim().toLowerCase().email('E-mail invalide'),
  telephone: z.string().trim().max(30).optional(),
};

const createResponsable = z.object(base);
const createTechnicien = z.object({ ...base, specialite: z.string().trim().min(1).max(80) });

const updateResponsable = createResponsable.partial().refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');
const updateTechnicien = z.object({ ...base, specialite: z.string().trim().min(1).max(80), disponible: z.boolean() })
  .partial().refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');

const statut = z.object({ statut: z.enum(['ACTIF', 'DESACTIVE']) });

const list = z.object({
  recherche: z.string().trim().max(80).optional(),
  statut: z.enum(['ACTIF', 'DESACTIVE']).optional(),
  disponible: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
});

module.exports = { createResponsable, createTechnicien, updateResponsable, updateTechnicien, statut, list };
