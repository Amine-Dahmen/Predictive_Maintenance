// Point d'entrée de toutes les routes /api.
// Tout ce qui est déclaré après router.use(authenticate()) exige un JWT valide.
const router = require('express').Router();
const { authenticate } = require('./middlewares/auth');

const authRoutes = require('./modules/auth/auth.routes');
const { responsables, techniciens } = require('./modules/utilisateurs/utilisateurs.routes');
const { machines, capteurs } = require('./modules/machines/machines.routes');
const alertes = require('./modules/alertes/alertes.routes');
const interventions = require('./modules/interventions/interventions.routes');
const ordresFabrication = require('./modules/ordres-fabrication/of.routes');
const indicateurs = require('./modules/indicateurs/indicateurs.routes');
const stream = require('./realtime/stream.routes');
const notifications = require('./modules/notifications/notifications.routes');
const rapports = require('./modules/rapports/rapports.routes');
const firmware = require('./modules/firmware/firmware.routes');
const predictions = require('./modules/predictions/predictions.routes');
const mqttService = require('./mqtt/mqtt.client');

// ---------- Routes publiques ----------
router.get('/health', (req, res) => res.json({ statut: 'ok', mqtt: mqttService.isConnected() ? 'connecte' : 'deconnecte' }));
router.use('/auth', authRoutes);
router.use('/stream', stream); // authentification par ?token= gérée dans la route
router.use('/firmware/telechargement', firmware.telechargement); // US-46 : jeton de déploiement à la place du JWT

// ---------- Routes protégées ----------
router.use(authenticate());
router.use('/responsables', responsables);
router.use('/techniciens', techniciens);
router.use('/machines/:id/firmware', firmware.parMachine);
router.use('/machines', machines);
router.use('/capteurs', capteurs);
router.use('/alertes', alertes);
router.use('/interventions', interventions);
router.use('/ordres-fabrication', ordresFabrication);
router.use('/indicateurs', indicateurs);
router.use('/notifications', notifications);
router.use('/rapports', rapports);
router.use('/firmware', firmware.gestion);
router.use('/predictions', predictions);

module.exports = router;
