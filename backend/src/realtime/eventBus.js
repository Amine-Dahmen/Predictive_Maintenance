// Bus d'événements interne. Les services publient ici, le flux SSE (/api/stream) relaie au front.
// Événements : mesure.recue, machine.etat, alerte.creee, alerte.maj, intervention.maj, intervention.affectee, capteur.etat
const { EventEmitter } = require('events');

const bus = new EventEmitter();
bus.setMaxListeners(200);

/**
 * @param {string} type        nom de l'événement
 * @param {object} data        contenu envoyé au front
 * @param {object} [cible]     { roles: [...], userId } pour restreindre les destinataires
 */
function publish(type, data, cible = {}) {
  bus.emit('event', { type, data, cible, date: new Date().toISOString() });
}

module.exports = { bus, publish };
