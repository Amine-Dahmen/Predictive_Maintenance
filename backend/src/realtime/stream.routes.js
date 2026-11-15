// Flux temps réel HTTP (Server-Sent Events) : GET /api/stream?token=<accessToken>
// Le front l'ouvre avec : new EventSource(`${API}/api/stream?token=${accessToken}`)
const router = require('express').Router();
const { authenticate } = require('../middlewares/auth');
const { bus } = require('./eventBus');

router.get('/',
  (req, res, next) => { req.allowQueryToken = true; next(); },
  authenticate(),
  (req, res) => {
    res.set({
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    res.flushHeaders();
    // identifiant numérique relu en base par authenticate(), flux text/event-stream (pas de HTML)
    // nosemgrep: ajinabraham.njsscan.xss.xss_node.express_xss
    res.write(`event: connecte\ndata: ${JSON.stringify({ utilisateur: Number(req.user.id) })}\n\n`);

    const user = req.user;
    const onEvent = (evt) => {
      const { roles, userId, interne } = evt.cible || {};
      if (evt.type === 'session.revoquee' && userId === user.id) {
        res.write(`event: session.revoquee\ndata: {}\n\n`);
        res.end();
        return;
      }
      if (interne) return;
      if (roles && !roles.includes(user.role) && userId !== user.id) return;
      if (!roles && userId && userId !== user.id) return;
      res.write(`event: ${evt.type}\ndata: ${JSON.stringify({ ...evt.data, date: evt.date })}\n\n`);
    };
    bus.on('event', onEvent);

    // Battement de cœur pour garder la connexion ouverte derrière les proxys
    const ping = setInterval(() => res.write(': ping\n\n'), 25000);
    req.on('close', () => { clearInterval(ping); bus.off('event', onEvent); });
  });

module.exports = router;
