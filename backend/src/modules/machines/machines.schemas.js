const { z, periode } = require('../../utils/schemas');
const { TYPES_MESURE } = require('../../utils/mesures');

const ETATS = ['NORMAL', 'ALERTE', 'PANNE', 'EN_MAINTENANCE', 'SANS_DONNEES'];

const machineFields = z.object({
  code: z.string().trim().min(1).max(40).regex(/^[A-Za-z0-9_-]+$/, 'Lettres, chiffres, - et _ uniquement'),
  nom: z.string().trim().min(1).max(120),
  emplacement: z.string().trim().max(120).optional(),
});
// kitPredimaint : crée aussi les 4 capteurs de la carte ESP32 (courant, vibration, température, humidité)
// avec leurs seuils par défaut
const createMachine = machineFields.extend({ kitPredimaint: z.boolean().optional() });
const updateMachine = machineFields.partial().refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');
// US-34 : coût horaire d'un arrêt de production
const coutMachine = z.object({ coutHoraireArret: z.number().min(0).max(1e7) });

// US-29 : déclaration manuelle d'une panne (crée une intervention curative)
const declarerPanne = z.object({
  description: z.string().trim().min(3).max(2000),
  debutPanne: z.coerce.date().refine((d) => d <= new Date(Date.now() + 60000), 'Le début de la panne ne peut pas être dans le futur').optional(),
  priorite: z.enum(['BASSE', 'MOYENNE', 'HAUTE', 'URGENTE']).optional(),
  // US-14 : affectation immédiate de la réparation à un technicien (facultative)
  technicienId: z.number().int().positive().optional(),
  echeance: z.coerce.date().refine((d) => d > new Date(), "L'échéance doit être dans le futur").optional(),
}).refine((d) => !d.technicienId || d.echeance, { message: 'Échéance obligatoire pour affecter la réparation', path: ['echeance'] });

// US-32 : ?ids=1,2,3
const comparaison = periode.and(z.object({
  ids: z.string().regex(/^\d+(,\d+)*$/, 'ids : liste d\'identifiants séparés par des virgules')
    .transform((v) => [...new Set(v.split(',').map(Number))])
    .refine((a) => a.length >= 2 && a.length <= 10, 'Choisissez entre 2 et 10 machines'),
  type: z.enum(TYPES_MESURE).optional(),
}));

// US-39 : soit gain/offset explicites, soit valeurReference (la mesure actuelle doit valoir cette référence)
const calibration = z.object({
  gain: z.number().positive().max(1000).optional(),
  offset: z.number().min(-10000).max(10000).optional(),
  valeurReference: z.number().min(-10000).max(10000).optional(),
}).refine((o) => o.gain !== undefined || o.offset !== undefined || o.valeurReference !== undefined, 'Aucun paramètre de calibration')
  .refine((o) => !(o.offset !== undefined && o.valeurReference !== undefined), { message: 'offset et valeurReference sont exclusifs', path: ['valeurReference'] });

// US-37 : identifiant du nouveau capteur (généré s'il est omis)
const remplacerCapteur = z.object({
  identifiant: z.string().trim().min(3).max(60).regex(/^[A-Za-z0-9_-]+$/, 'Lettres, chiffres, - et _ uniquement').optional(),
});

const listMachines = z.object({
  etat: z.enum(ETATS).optional(),
  recherche: z.string().trim().max(80).optional(),
});

// L'identifiant du capteur est utilisé dans les topics MQTT : pas d'espace ni de caractère spécial MQTT (+ # /)
const createCapteur = z.object({
  identifiant: z.string().trim().min(3).max(60).regex(/^[A-Za-z0-9_-]+$/, 'Lettres, chiffres, - et _ uniquement'),
  type: z.enum(TYPES_MESURE),
  unite: z.string().trim().min(1).max(10).optional(),
});
const updateCapteur = z.object({
  actif: z.boolean().optional(),
  unite: z.string().trim().min(1).max(10).optional(),
}).refine((o) => Object.keys(o).length > 0, 'Aucun champ à modifier');

const seuilParams = z.object({
  id: z.coerce.number().int().positive(),
  typeMesure: z.enum(TYPES_MESURE),
});
const seuilBody = z.object({
  seuilAlerte: z.number().positive('Le seuil doit être positif'),
  seuilCritique: z.number().positive('Le seuil doit être positif'),
}).refine((s) => s.seuilCritique > s.seuilAlerte, { message: "Le seuil critique doit être supérieur au seuil d'alerte", path: ['seuilCritique'] });

const mesuresQuery = periode.and(z.object({
  type: z.enum(TYPES_MESURE).optional(),
  limit: z.coerce.number().int().min(1).max(5000).default(500),
}));

module.exports = { coutMachine, declarerPanne, comparaison, calibration, remplacerCapteur, createMachine, updateMachine, listMachines, createCapteur, updateCapteur, seuilParams, seuilBody, mesuresQuery, periode };
