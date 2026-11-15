// Petit logger horodaté. Remplaçable par pino ou winston si besoin.
const ts = () => new Date().toISOString();

module.exports = {
  info: (...args) => console.log(`[${ts()}] INFO `, ...args),
  warn: (...args) => console.warn(`[${ts()}] WARN `, ...args),
  error: (...args) => console.error(`[${ts()}] ERROR`, ...args),
};
