// US-46 : publie une version du firmware pour la mise à jour à distance.
// Usage : npm run firmware:publier [-- <version>]
//   La version par défaut est FIRMWARE_VERSION de partie_embarque/src/config.py (elle doit y correspondre :
//   la carte annonce cette valeur après la mise à jour). credentials.py n'est JAMAIS copié.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const SRC = path.resolve(__dirname, '..', '..', 'partie_embarque', 'src');
const FICHIERS = ['main.py', 'config.py', 'net.py', 'sensors.py', 'alerts.py', 'buffer.py', 'ota.py'];
const DEST = path.resolve(__dirname, '..', process.env.FIRMWARE_DIR || 'firmware');

const config = fs.readFileSync(path.join(SRC, 'config.py'), 'utf8');
const versionConfig = (config.match(/^FIRMWARE_VERSION\s*=\s*"([^"]+)"/m) || [])[1];
const version = process.argv[2] || versionConfig;
if (!version || !/^[0-9A-Za-z._-]{1,40}$/.test(version)) { console.error('Version invalide ou absente'); process.exit(1); }
if (version !== versionConfig) {
  console.error(`La version demandée (${version}) diffère de FIRMWARE_VERSION dans config.py (${versionConfig}).`);
  process.exit(1);
}

const dir = path.join(DEST, version);
if (fs.existsSync(dir)) { console.error(`La version ${version} est déjà publiée (${dir}). Augmentez FIRMWARE_VERSION.`); process.exit(1); }
fs.mkdirSync(dir, { recursive: true });
const fichiers = FICHIERS.map((nom) => {
  const data = fs.readFileSync(path.join(SRC, nom));
  fs.writeFileSync(path.join(dir, nom), data);
  return { nom, taille: data.length, sha256: crypto.createHash('sha256').update(data).digest('hex') };
});
fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ version, publieLe: new Date().toISOString(), fichiers }, null, 2));
console.log(`Firmware ${version} publié dans ${dir} (${fichiers.length} fichiers)`);
