// Types des réponses de l'API (voir backend/docs/API.md). Aucune dépendance Angular.

export type Role = 'DIRECTEUR' | 'RESPONSABLE' | 'TECHNICIEN';

export interface User {
  id: number;
  nom: string;
  prenom: string;
  email: string;
  telephone?: string | null;
  statut: string;
  role: Role;
  doitChangerMotDePasse?: boolean;
  specialite?: string | null;
  disponible?: boolean;
}

export type MachineState = 'NORMAL' | 'ALERTE' | 'PANNE' | 'EN_MAINTENANCE' | 'SANS_DONNEES';
export type SensorType = 'COURANT' | 'VIBRATION' | 'TEMPERATURE' | 'HUMIDITE';

export interface Sensor {
  id: number;
  identifiant: string;
  machineId: number;
  type: SensorType;
  unite: string;
  actif: boolean;
  enLigne: boolean;
  derniereMesureAt: string | null;
  derniereValeur?: number | null;
}

export interface Threshold {
  id: number;
  typeMesure: SensorType;
  seuilAlerte: number;
  seuilCritique: number;
  updatedAt: string;
}

export interface Machine {
  id: number;
  code: string;
  nom: string;
  emplacement: string | null;
  etat: MachineState;
  createdAt: string;
  updatedAt: string;
  nbCapteurs?: number;
  capteurs?: Sensor[];
  seuils?: Threshold[];
}

export type AlertLevel = 'ALERTE' | 'CRITIQUE';
export type AlertStatus = 'OUVERTE' | 'PRISE_EN_COMPTE' | 'CLOTUREE';

export interface Alert {
  id: number;
  machineId: number;
  machineCode: string;
  machineNom: string;
  capteurId: number;
  capteur: string;
  typeMesure: SensorType;
  unite: string;
  niveau: AlertLevel;
  valeur: number;
  seuilDepasse: number;
  statut: AlertStatus;
  priseEnCompteParId: number | null;
  priseEnCompteAt: string | null;
  clotureeAt: string | null;
  commentaire: string | null;
  createdAt: string;
  enRetard: boolean;
}

export interface Measure {
  id: number;
  valeur: number;
  horodatage: string;
  capteurId: number;
  identifiant: string;
  type: SensorType;
  unite: string;
}

export interface Order {
  id: number;
  numero: string;
  produit: string;
  quantitePrevue: number;
  quantiteProduite: number;
  statut: string;
  machineId: number;
}

// ---------- Libellés affichés ----------

export const ROLE_LABELS: Record<Role, string> = {
  DIRECTEUR: 'Directeur de production',
  RESPONSABLE: 'Responsable de maintenance',
  TECHNICIEN: 'Technicien de maintenance',
};

export const STATE_LABELS: Record<MachineState, string> = {
  NORMAL: 'Normal',
  ALERTE: 'Alerte',
  PANNE: 'Panne',
  EN_MAINTENANCE: 'En maintenance',
  SANS_DONNEES: 'Sans données',
};

export const SENSOR_LABELS: Record<SensorType, string> = {
  COURANT: 'Courant',
  VIBRATION: 'Vibration',
  TEMPERATURE: 'Température',
  HUMIDITE: 'Humidité',
};

export const SENSOR_TYPES: SensorType[] = ['COURANT', 'VIBRATION', 'TEMPERATURE', 'HUMIDITE'];

export const ALERT_STATUS_LABELS: Record<AlertStatus, string> = {
  OUVERTE: 'Ouverte',
  PRISE_EN_COMPTE: 'Prise en compte',
  CLOTUREE: 'Clôturée',
};
