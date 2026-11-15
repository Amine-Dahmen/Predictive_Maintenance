// US-38 : canaux de notification des alertes, configurés par le directeur.
//   APP   : notification (toast / notification système) dans les applications. Le flux temps réel transmet
//           toujours les données ; le champ « notifier » dit seulement s'il faut alerter l'utilisateur.
//   EMAIL : e-mail aux responsables actifs (+ destinataires supplémentaires) à partir du niveau choisi.
const { query } = require('../../config/db');
const env = require('../../config/env');
const logger = require('../../utils/logger');
const AppError = require('../../utils/AppError');

const NIVEAUX = { ALERTE: 1, CRITIQUE: 2 };
const atteint = (niveau, niveauMin) => (NIVEAUX[niveau] || 0) >= (NIVEAUX[niveauMin] || 0);

let transport; // créé à la première utilisation
function getTransport() {
  if (transport !== undefined) return transport;
  if (!env.SMTP_HOST) { transport = null; return null; }
  const nodemailer = require('nodemailer');
  transport = nodemailer.createTransport({
    host: env.SMTP_HOST, port: env.SMTP_PORT, secure: env.SMTP_SECURE,
    auth: env.SMTP_USER ? { user: env.SMTP_USER, pass: env.SMTP_PASSWORD } : undefined,
  });
  return transport;
}

const COLS = `canal, actif, niveau_min AS "niveauMin", destinataires, updated_at AS "updatedAt"`;

const lister = async () => (await query(`SELECT ${COLS} FROM canaux_notification ORDER BY canal`)).rows;

async function modifier(canal, { actif, niveauMin, destinataires }, user) {
  const { rows } = await query(
    `UPDATE canaux_notification SET actif = COALESCE($2, actif), niveau_min = COALESCE($3, niveau_min),
       destinataires = CASE WHEN $4::boolean THEN $5 ELSE destinataires END, modifie_par = $6, updated_at = NOW()
     WHERE canal = $1 RETURNING ${COLS}`,
    [canal, actif ?? null, niveauMin ?? null, destinataires !== undefined, destinataires ?? null, user.id],
  );
  if (!rows[0]) throw AppError.notFound('Canal inconnu');
  return rows[0];
}

async function canaux() {
  const map = {};
  for (const c of await lister()) map[c.canal] = c;
  return map;
}

// Faut-il afficher une notification dans les applications pour cette alerte ?
async function notifierApp(alerte) {
  const app = (await canaux()).APP;
  return !app || (app.actif && atteint(alerte.niveau, app.niveauMin));
}

function contenuEmail(a) {
  const sujet = `[PrédiMaint] ${a.niveau} sur ${a.machineCode} : ${a.typeMesure}`;
  const texte = [
    `Machine : ${a.machineCode} (${a.machineNom})`,
    `Mesure : ${a.typeMesure} = ${a.valeur} ${a.unite || ''} (seuil ${a.seuilDepasse})`,
    `Niveau : ${a.niveau}`,
    `Date : ${new Date(a.createdAt).toLocaleString('fr-FR')}`,
    '', 'Ouvrez l’application pour prendre en compte l’alerte.',
  ].join('\n');
  return { sujet, texte };
}

async function envoyerEmail(alerte) {
  const email = (await canaux()).EMAIL;
  if (!email || !email.actif || !atteint(alerte.niveau, email.niveauMin)) return { envoye: false };
  const { rows } = await query(`SELECT email FROM utilisateurs WHERE role = 'RESPONSABLE' AND statut = 'ACTIF'`);
  const extra = (email.destinataires || '').split(',').map((e) => e.trim()).filter(Boolean);
  const to = [...new Set([...rows.map((r) => r.email), ...extra])];
  if (!to.length) return { envoye: false };
  const { sujet, texte } = contenuEmail(alerte);
  const t = getTransport();
  if (!t) {
    logger.info(`E-mail d'alerte (SMTP non configuré) -> ${to.join(', ')} : ${sujet}`);
    return { envoye: false, destinataires: to };
  }
  await t.sendMail({ from: env.SMTP_FROM, to, subject: sujet, text: texte });
  logger.info(`E-mail d'alerte envoyé à ${to.length} destinataire(s) : ${sujet}`);
  return { envoye: true, destinataires: to };
}

// Appelé par le traitement MQTT : ne doit jamais faire échouer l'enregistrement de la mesure
function alerteSansAttendre(alerte) {
  envoyerEmail(alerte).catch((e) => logger.error("Envoi de l'e-mail d'alerte impossible :", e.message));
}

module.exports = { lister, modifier, notifierApp, envoyerEmail, alerteSansAttendre, contenuEmail, atteint };
