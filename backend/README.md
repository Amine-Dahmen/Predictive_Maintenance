# Backend — Application IoT de maintenance prédictive

API REST (Node.js / Express) + passerelle MQTT + PostgreSQL.

```
 ESP32 (courant, vibration,  ──MQTT──▶ Mosquitto ──MQTT──▶ Backend Node.js ──HTTP/JSON + SSE──▶ Front web / mobile
        température, humidité)                                  │
 firmware : ../partie_embarque                             PostgreSQL
```

## Architecture du code (en couches)

```
backend/
├── src/
│   ├── server.js               démarrage : base -> HTTP -> MQTT -> surveillance capteurs
│   ├── app.js                  Express : helmet, CORS, rate limit, routes, gestion d'erreurs
│   ├── routes.js               montage des routes publiques / protégées par JWT
│   ├── config/                 env.js (variables validées), db.js (pool PostgreSQL, transactions)
│   ├── middlewares/            auth (JWT + rôles), validate (zod), rateLimit, errorHandler
│   ├── modules/                un dossier par domaine du diagramme de classes
│   │   ├── auth/               login, refresh, logout, changement de mot de passe
│   │   ├── utilisateurs/       responsables et techniciens
│   │   ├── machines/           machines, capteurs, seuils, mesures, historique
│   │   ├── alertes/
│   │   ├── interventions/      interventions + comptes rendus
│   │   ├── ordres-fabrication/
│   │   └── indicateurs/        MTBF, MTTR, disponibilité, TRS, dashboard
│   │       chaque module : *.routes.js -> *.controller.js -> *.service.js -> *.repository.js (+ *.schemas.js)
│   ├── mqtt/                   client MQTT, contrat des topics, traitement des mesures (moteur d'alertes)
│   ├── services/               état des machines, surveillance des capteurs inactifs
│   ├── realtime/               bus d'événements + flux SSE /api/stream
│   ├── db/                     migrations SQL, migrate.js, seed.js
│   └── utils/                  erreurs, jetons, mots de passe, logger, schémas communs
├── mosquitto/config/           mosquitto.conf (sans anonyme) + acl (droits par ESP32)
├── scripts/                    simulateur ESP32, création des comptes MQTT
├── docs/                       API.md (équipe front), CONTRAT_MQTT.md (équipe embarquée)
└── tests/                      tests unitaires (node --test)
```

Rôle de chaque couche :
- **routes** : URL, rôles autorisés, validation des entrées ;
- **controller** : lit la requête, appelle le service, renvoie la réponse HTTP ;
- **service** : règles métier (cycle des interventions, alertes, calculs) ;
- **repository** : requêtes SQL paramétrées, rien d'autre.

## Correspondance avec le diagramme de classes

| Classe | Table | Module |
|---|---|---|
| Utilisateur, DirecteurProduction, ResponsableMaintenance, Technicien | `utilisateurs` (colonne `role`) | auth, utilisateurs |
| Machine | `machines` | machines |
| Capteur | `capteurs` | machines |
| Mesure | `mesures` | mqtt, machines |
| Seuil | `seuils` | machines |
| Alerte | `alertes` | alertes, mqtt |
| Intervention | `interventions` | interventions |
| CompteRendu | `comptes_rendus` | interventions |
| OrdreFabrication | `ordres_fabrication` | ordres-fabrication |
| méthodes calculerMTBF / MTTR / TRS | — (calculées) | indicateurs |

## Installation (développement)

Prérequis : Node.js 18+, Docker Desktop et Mosquitto (local).

### Démarrage recommandé avec Docker

Docker Desktop doit être démarré. Depuis le dossier `backend` :

```powershell
docker compose up --build
```

Cette commande démarre PostgreSQL dans le conteneur `db`, applique les migrations,
mais l'API Node.js reste lancée localement.
Le broker Mosquitto reste à démarrer séparément avec `npm run mqtt` si le MQTT est utilisé.

Après le démarrage de PostgreSQL, ouvre un autre terminal et lance l'API :

```powershell
npm install
npm run db:migrate
npm run db:seed
npm run dev
```

Pour arrêter les conteneurs :

```powershell
docker compose down
```

Les données PostgreSQL restent dans le volume Docker `postgres_data`.

```bash
cd backend
Copy-Item .env.example .env        # pour lancer le backend hors Docker
npm install

# 1. Comptes MQTT (crée le compte backend + machine M01 dans mosquitto/config/passwd)
npm run mqtt:users

# 2. Démarrer le broker Mosquitto (dans un terminal dédié)
npm run mqtt

# 3. Base de données (uniquement si le backend est lancé hors Docker)
npm run db:migrate                 # crée les tables
npm run db:seed                    # crée le directeur + la machine de démo M01

# 4. API (dans un autre terminal)
npm run dev                        # http://localhost:3000/api/health ou Swagger /api/docs

# 5. Simuler un ESP32 (dans un 3e terminal)
npm run simulateur                 # ou : node scripts/simulateur-esp32.js M01 anomalie
```

Sous **Linux / macOS**, les étapes 1 et 2 utilisent les scripts bash (Mosquitto installé avec le gestionnaire de paquets) :

```bash
cp .env.example .env
npm run mqtt:users:linux                                  # comptes backend + M01
bash scripts/creer-utilisateurs-mqtt.sh M02 esp32_M02_pwd # compte d'une autre machine
npm run mqtt:linux                                        # broker sur le port 1883
MQTT_PORT=1884 npm run mqtt:linux                         # autre port si un mosquitto système occupe 1883
                                                          #   (mettre alors MQTT_URL=mqtt://localhost:1884 dans .env)
```

Sans `docker compose`, PostgreSQL peut aussi être lancé avec :
`docker run -d --name maintenance-db -e POSTGRES_DB=maintenance_iot -e POSTGRES_USER=maint -e POSTGRES_PASSWORD=maint_password -p 5432:5432 postgres:16-alpine`

Connexion initiale : `directeur@usine.local` / `ChangezMoi123!`, puis changement de mot de passe obligatoire.
Le fichier `api.http` contient des requêtes prêtes à l'emploi (extension VS Code « REST Client »).

Tests : `npm test`.

## Sécurité

**Authentification JWT**
- Jeton d'accès HS256, valable 15 min, algorithme imposé à la vérification (pas d'attaque `alg: none`).
- Refresh token aléatoire de 48 octets, valable 7 jours, **stocké haché** (HMAC-SHA256), **à usage unique** (rotation).
  S'il est réutilisé (vol probable), toutes les sessions de l'utilisateur sont révoquées.
- À chaque requête, le compte est relu en base : un compte désactivé est bloqué immédiatement, même avec un jeton valide.
- Secrets dans `.env` (jamais sur GitHub), au moins 32 caractères, différents pour l'accès et le refresh.

**Comptes et mots de passe**
- Hachage bcrypt (12 tours). Le hash n'est jamais renvoyé par l'API.
- Mot de passe provisoire à la création, changement obligatoire à la première connexion.
- Politique : 10 caractères minimum, avec une minuscule, une majuscule et un chiffre.
- Message d'erreur identique pour un e-mail inconnu ou un mauvais mot de passe, avec un temps de réponse identique.
- Limitation : 10 tentatives de connexion par 15 min et par IP ; 300 requêtes par minute sur l'API.

**Autorisations**
- Contrôle par rôle sur chaque route (`authorize(...)`).
- Contrôle de propriété : un technicien ne voit et ne modifie que ses propres interventions.

**Entrées et base de données**
- Toutes les entrées sont validées par zod ; les champs inconnus sont supprimés.
- Requêtes SQL 100 % paramétrées (aucune concaténation de données utilisateur) : pas d'injection SQL.
- Contraintes en base : unicité, clés étrangères, seuil critique supérieur au seuil d'alerte, une seule alerte ouverte par capteur.

**HTTP**
- `helmet` (en-têtes de sécurité), CORS limité aux origines déclarées, corps limité à 100 Ko, `x-powered-by` désactivé.
- Les erreurs internes ne révèlent aucun détail technique en production.

**MQTT**
- Connexions anonymes interdites ; un identifiant et un mot de passe par ESP32.
- ACL : un ESP32 ne peut publier que sur les topics de **sa** machine ; seul le backend lit les mesures.
- Le backend valide chaque message (format, taille, plage physique, machine connue) avant de l'enregistrer.
- Production : activer le listener TLS 8883 dans `mosquitto/config/mosquitto.conf`.

**En production**, ajoutez : HTTPS (reverse proxy nginx + certificat), `NODE_ENV=production`, mots de passe
PostgreSQL et MQTT forts, sauvegardes de la base.
