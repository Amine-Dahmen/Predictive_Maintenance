const { z } = require('../../utils/schemas');

const TYPES = ['PREVENTIVE', 'PREDICTIVE', 'CURATIVE'];
const PRIORITES = ['BASSE', 'MOYENNE', 'HAUTE', 'URGENTE'];
const STATUTS = ['A_AFFECTER', 'AFFECTEE', 'EN_COURS', 'CLOTUREE', 'ANNULEE'];

const future = z.coerce.date().refine((d) => d > new Date(), "L'échéance doit être dans le futur");

const create = z.object({
  type: z.enum(TYPES),
  machineId: z.number().int().positive().optional(),
  alerteId: z.number().int().positive().optional(),
  description: z.string().trim().min(3).max(2000),
  priorite: z.enum(PRIORITES).optional(),
  datePrevue: z.coerce.date().optional(),
  echeance: future.optional(),
  debutPanne: z.coerce.date().optional(),
})
  .refine((d) => d.type !== 'PREDICTIVE' || d.alerteId, { message: "Une intervention prédictive doit référencer l'alerte d'origine", path: ['alerteId'] })
  .refine((d) => d.type === 'PREDICTIVE' || d.machineId, { message: 'machineId est obligatoire', path: ['machineId'] })
  .refine((d) => d.type !== 'PREVENTIVE' || d.datePrevue, { message: 'Une intervention préventive doit avoir une date prévue', path: ['datePrevue'] })
  .refine((d) => d.type !== 'PREDICTIVE' || (d.priorite && d.echeance), { message: 'Priorité et échéance obligatoires', path: ['echeance'] });

const update = z.object({
  description: z.string().trim().min(3).max(2000).optional(),
  priorite: z.enum(PRIORITES).optional(),
  datePrevue: z.coerce.date().optional(),
  echeance: future.optional(),
}).refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');

const affecter = z.object({
  technicienId: z.number().int().positive(),
  echeance: future,
  priorite: z.enum(PRIORITES).optional(),
});

const list = z.object({
  statut: z.enum(STATUTS).optional(),
  type: z.enum(TYPES).optional(),
  machineId: z.coerce.number().int().positive().optional(),
  technicienId: z.coerce.number().int().positive().optional(),
  enRetard: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  // technicien : interventions à affecter que personne n'a encore prises
  aPrendre: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
});

const compteRendu = z.object({
  diagnostic: z.string().trim().max(5000).optional(),
  actions: z.string().trim().max(5000).optional(),
  piecesUtilisees: z.string().trim().max(2000).optional(),
});

const cloturer = z.object({ resultat: z.enum(['REMISE_EN_SERVICE', 'NON_RESOLU']) });

module.exports = { create, update, affecter, list, compteRendu, cloturer };
