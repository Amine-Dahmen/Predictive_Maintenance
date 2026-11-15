// Types de mesure gérés par la plateforme : une seule liste pour la validation de l'API,
// le traitement MQTT et les unités par défaut.
//
// Capteurs de la carte PrédiMaint (voir partie_embarque/README.md) :
//   COURANT      ACS712 (courant efficace)        A
//   VIBRATION    SW-420 (impulsions par seconde)   imp/s   (ou mm/s avec un accéléromètre)
//   TEMPERATURE  DHT22                             °C
//   HUMIDITE     DHT22                             %

const TYPES_MESURE = ['COURANT', 'VIBRATION', 'TEMPERATURE', 'HUMIDITE'];

const UNITES_PAR_DEFAUT = { COURANT: 'A', VIBRATION: 'imp/s', TEMPERATURE: '°C', HUMIDITE: '%' };

// Bornes physiques plausibles : au-delà, la mesure est considérée invalide (capteur ou câblage défectueux)
const PLAGES = {
  COURANT: [0, 1000],
  VIBRATION: [0, 10000],   // SW-420 : quelques milliers d'impulsions/s au maximum
  TEMPERATURE: [-40, 80],  // plage de mesure du DHT22
  HUMIDITE: [0, 100],
};

// Seuils (alerte, critique) appliqués aux capteurs de la carte PrédiMaint quand une machine est créée
// avec son kit de capteurs. Modifiables ensuite dans l'application (PUT /machines/:id/seuils/:type).
const SEUILS_PAR_DEFAUT = {
  COURANT: [3, 4.5],      // ACS712 5 A
  VIBRATION: [20, 50],    // impulsions/s du SW-420
  TEMPERATURE: [45, 60],
  HUMIDITE: [80, 90],
};

// Champ du message MQTT -> type de mesure
const CHAMPS_MQTT = { courant: 'COURANT', vibration: 'VIBRATION', temperature: 'TEMPERATURE', humidite: 'HUMIDITE' };

module.exports = { TYPES_MESURE, UNITES_PAR_DEFAUT, SEUILS_PAR_DEFAUT, PLAGES, CHAMPS_MQTT };
