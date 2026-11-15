// Schémas zod réutilisés par plusieurs modules
const { z } = require('zod');

const idParam = z.object({ id: z.coerce.number().int().positive() });

const password = z.string()
  .min(10, 'Au moins 10 caractères')
  .max(100)
  .regex(/[a-z]/, 'Au moins une minuscule')
  .regex(/[A-Z]/, 'Au moins une majuscule')
  .regex(/[0-9]/, 'Au moins un chiffre');

const periode = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
}).refine((p) => !p.from || !p.to || p.from < p.to, { message: 'La date de fin doit être après la date de début', path: ['to'] });

// Période par défaut : 30 derniers jours
function resolvePeriode({ from, to } = {}) {
  const end = to || new Date();
  const start = from || new Date(end.getTime() - 30 * 24 * 3600 * 1000);
  return { from: start, to: end };
}

module.exports = { z, idParam, password, periode, resolvePeriode };
