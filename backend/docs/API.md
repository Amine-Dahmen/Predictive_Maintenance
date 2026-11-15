# API REST — documentation pour l'équipe front (web et mobile)

URL de base : `http://<serveur>:3000/api` — tout est en JSON.

## 1. Authentification (JWT)

### Le principe
1. `POST /auth/login` renvoie un **accessToken** (valable 15 min) et un **refreshToken** (valable 7 jours).
2. Chaque requête envoie l'en-tête : `Authorization: Bearer <accessToken>`.
3. Quand l'API répond `401` avec le code `JETON_EXPIRE`, appelez `POST /auth/refresh` avec le refreshToken :
   vous recevez une **nouvelle paire** de jetons. L'ancien refreshToken ne fonctionne plus (rotation).
4. Si `/auth/refresh` répond `401`, renvoyez l'utilisateur vers l'écran de connexion.
5. À la déconnexion, appelez `POST /auth/logout` avec le refreshToken.

**Stockage conseillé** — web : accessToken en mémoire (variable), refreshToken en `sessionStorage` ;
mobile : stockage sécurisé (Keychain / Keystore, ex. `expo-secure-store`, `flutter_secure_storage`).

### Premier login
Un compte créé par un administrateur reçoit un **mot de passe provisoire**. Tant qu'il n'est pas changé,
toutes les routes répondent `403 CHANGEMENT_MDP_REQUIS` sauf `/auth/me` et `/auth/change-password`.
Le login renvoie `utilisateur.doitChangerMotDePasse: true` : affichez directement l'écran de changement.

Politique de mot de passe : 10 caractères minimum, avec une minuscule, une majuscule et un chiffre.

| Méthode | Route | Corps | Réponse |
|---|---|---|---|
| POST | `/auth/login` | `{ email, motDePasse }` | `{ accessToken, refreshToken, tokenType, utilisateur }` |
| POST | `/auth/refresh` | `{ refreshToken }` | nouvelle paire + `utilisateur` |
| POST | `/auth/logout` | `{ refreshToken }` | `204` |
| GET | `/auth/me` | — | utilisateur connecté |
| POST | `/auth/change-password` | `{ ancienMotDePasse, nouveauMotDePasse }` | nouvelle paire (les autres appareils sont déconnectés) |

Après 10 échecs de connexion en 15 minutes depuis la même adresse IP, l'API répond `429`.

## 2. Format des erreurs

```json
{ "erreur": { "code": "REQUETE_INVALIDE", "message": "Données invalides",
  "details": [ { "champ": "seuilCritique", "message": "Le seuil critique doit être supérieur au seuil d'alerte" } ] } }
```

| HTTP | Codes possibles | Signification |
|---|---|---|
| 400 | `REQUETE_INVALIDE` | champ manquant ou invalide (voir `details`) |
| 401 | `NON_AUTHENTIFIE`, `JETON_EXPIRE`, `JETON_INVALIDE`, `IDENTIFIANTS_INVALIDES`, `SESSION_INVALIDE` | pas connecté ou jeton à renouveler |
| 403 | `ACCES_REFUSE`, `CHANGEMENT_MDP_REQUIS` | rôle insuffisant / mot de passe à changer |
| 404 | `INTROUVABLE` | ressource inexistante (ou non visible pour ce technicien) |
| 409 | `CONFLIT` | doublon, ou action impossible dans l'état actuel |
| 429 | `TROP_DE_REQUETES` | trop de requêtes |

## 3. Rôles

`DIRECTEUR` (D), `RESPONSABLE` (R), `TECHNICIEN` (T). La colonne « Rôles » indique qui peut appeler la route.

## 4. Routes

### Utilisateurs
| Méthode | Route | Rôles | Corps / filtres |
|---|---|---|---|
| GET | `/responsables` | D | `?recherche=&statut=ACTIF|DESACTIVE` |
| POST | `/responsables` | D | `{ nom, prenom, email, telephone? }` → renvoie `motDePasseProvisoire` (une seule fois) |
| GET / PATCH | `/responsables/:id` | D | champs à modifier |
| PATCH | `/responsables/:id/statut` | D | `{ statut: "DESACTIVE" }` (le compte est déconnecté immédiatement) |
| GET | `/techniciens` | D, R | `?recherche=&statut=&disponible=true` — inclut `interventionsEnCours` |
| POST | `/techniciens` | R | `{ nom, prenom, email, telephone?, specialite }` → `motDePasseProvisoire` |
| GET / PATCH | `/techniciens/:id` | D, R / R | `{ ..., disponible? }` |
| PATCH | `/techniciens/:id/statut` | R | `{ statut }` |

### Machines, capteurs, seuils, mesures
| Méthode | Route | Rôles | Remarques |
|---|---|---|---|
| GET | `/machines` | D, R, T | `?etat=NORMAL|ALERTE|PANNE|EN_MAINTENANCE|SANS_DONNEES&recherche=` |
| GET | `/machines/:id` | D, R, T | machine + `capteurs` (avec `derniereValeur`, `enLigne`) + `seuils` |
| POST | `/machines` | R | `{ code, nom, emplacement?, kitPredimaint? }` — `code` = identifiant MQTT de l'ESP32. Avec `kitPredimaint: true`, crée aussi les 4 capteurs de la carte (`<code>-COURANT`, `-VIBRATION`, `-TEMPERATURE`, `-HUMIDITE`) et leurs seuils par défaut |
| PATCH | `/machines/:id` | R | |
| GET | `/machines/:id/historique` | D, R, T | `?from=&to=` alertes + interventions, du plus récent au plus ancien |
| GET | `/machines/:id/mesures` | D, R, T | `?type=COURANT|VIBRATION|TEMPERATURE|HUMIDITE&from=&to=&limit=500` (pour les courbes) |
| POST | `/machines/:id/capteurs` | R | `{ identifiant, type: "COURANT"|"VIBRATION"|"TEMPERATURE"|"HUMIDITE", unite? }` — unité par défaut : A, imp/s, °C, % |
| PATCH | `/capteurs/:id` | R | `{ actif?, unite? }` |
| GET | `/machines/:id/seuils` | D, R, T | |
| PUT | `/machines/:id/seuils/:typeMesure` | R | `{ seuilAlerte, seuilCritique }` (critique > alerte > 0) — envoyés aussi à la carte ESP32 sur MQTT (US-11) |

Couleurs à afficher (toujours avec le libellé) : `NORMAL` vert, `ALERTE` orange, `PANNE` rouge,
`EN_MAINTENANCE` bleu, `SANS_DONNEES` gris.

### Alertes
| Méthode | Route | Rôles | Remarques |
|---|---|---|---|
| GET | `/alertes` | D, R, T | `?machineId=&statut=OUVERTE|PRISE_EN_COMPTE|CLOTUREE&niveau=ALERTE|CRITIQUE&from=&to=&limit=` — champs `enRetard` (ouverte depuis plus de 30 min), `mesureAt` et `delaiDetectionS` (délai entre la mesure et la création de l'alerte, US-43) |
| GET | `/alertes/par-machine` | D, R, T | nombre d'alertes par machine sur la période |
| GET | `/alertes/:id` | D, R, T | |
| PATCH | `/alertes/:id/prise-en-compte` | R, T | accusé de réception (US-03) |
| PATCH | `/alertes/:id/cloture` | R | `{ commentaire }` |

### Interventions
Cycle : `A_AFFECTER` → `AFFECTEE` → `EN_COURS` → `CLOTUREE` (ou `ANNULEE` avant démarrage).

| Méthode | Route | Rôles | Corps / remarques |
|---|---|---|---|
| GET | `/interventions` | D, R, T | `?statut=&type=&machineId=&technicienId=&enRetard=true` — le technicien ne reçoit que les siennes, triées par priorité puis échéance |
| GET | `/interventions/:id` | D, R, T | détail + `compteRendu` + `alerte` d'origine |
| POST | `/interventions` | R | voir exemples ci-dessous |
| PATCH | `/interventions/:id` | R | `{ description?, priorite?, datePrevue?, echeance? }` (non démarrée) |
| PATCH | `/interventions/:id/affecter` | R | `{ technicienId, echeance, priorite? }` → `avertissements` si le technicien est déjà pris ce jour-là |
| PATCH | `/interventions/:id/annuler` | R | |
| PATCH | `/interventions/:id/demarrer` | T (affecté) | |
| GET | `/interventions/:id/compte-rendu` | D, R, T | |
| PUT | `/interventions/:id/compte-rendu` | T (affecté, en cours) | `{ diagnostic?, actions?, piecesUtilisees? }` (enregistrement en brouillon) |
| PATCH | `/interventions/:id/cloturer` | T (affecté) | `{ resultat: "REMISE_EN_SERVICE"|"NON_RESOLU" }` — exige diagnostic et actions |

```json
// Préventive
{ "type": "PREVENTIVE", "machineId": 1, "description": "Graissage mensuel", "datePrevue": "2026-11-02T08:00:00Z" }
// Prédictive (depuis une alerte : la machine est déduite de l'alerte)
{ "type": "PREDICTIVE", "alerteId": 12, "description": "Vibration anormale", "priorite": "HAUTE", "echeance": "2026-10-20T17:00:00Z" }
// Curative (priorité URGENTE par défaut, debutPanne = maintenant par défaut)
{ "type": "CURATIVE", "machineId": 2, "description": "Moteur bloqué" }
```

### Ordres de fabrication
| Méthode | Route | Rôles | Remarques |
|---|---|---|---|
| GET | `/ordres-fabrication` | D, R | `?statut=PLANIFIE|EN_COURS|TERMINE&machineId=&from=&to=` |
| POST | `/ordres-fabrication` | D | `{ numero, machineId, produit, quantitePrevue, tempsCycleS?, dateDebut?, dateFin? }` |
| PATCH | `/ordres-fabrication/:id` | D | `{ quantiteProduite?, quantiteRebutee?, statut?, ... }` |

### Indicateurs et tableaux de bord
| Méthode | Route | Rôles | Remarques |
|---|---|---|---|
| GET | `/indicateurs` | D, R | `?machineId=&from=&to=` (30 derniers jours par défaut) → `global` + `machines[]` |
| GET | `/indicateurs/dashboard` | D, R | compteurs (machines par état, alertes, interventions, OF) + indicateurs globaux |

Chaque indicateur contient : `mtbfH`, `mttrH`, `tempsArretH`, `nbPannes`, `disponibilite`, `performance`,
`qualite`, `trs` (valeurs entre 0 et 1), `trsIncomplet` et `messages` (ex. « Aucune panne sur la période : MTBF non calculable »).
Une valeur `null` signifie « données insuffisantes » : affichez le message, pas 0.

### Release 3

D = directeur, R = responsable, T = technicien.

| Méthode | Route | Rôles | US | Description |
|---|---|---|---|---|
| PATCH | `/alertes/:id/fausse-alerte` | R | US-31 | `{ commentaire }` : clôture et marque l'alerte (`fausseAlerte: true`), exclue des statistiques. Filtre `GET /alertes?fausseAlerte=true` |
| POST | `/machines/:id/pannes` | R, T | US-29 | `{ description, debutPanne?, priorite?, technicienId?, echeance? }` : crée la réparation (intervention CURATIVE, machine en PANNE, comptée dans MTBF/MTTR) ; avec `technicienId` + `echeance` elle est affectée tout de suite (US-14). La panne prend fin quand le technicien clôture la réparation avec `REMISE_EN_SERVICE`. Déclarée par un technicien, la réparation lui est affectée d'office |
| GET | `/interventions?aPrendre=true` | tous | extension US-26 | interventions à affecter sans technicien (le technicien voit aussi leur détail) |
| PATCH | `/interventions/:id/prendre-en-charge` | T | extension US-26 | le technicien se l'affecte (échéance existante, sinon +24 h) ; 409 si déjà prise ; le responsable est notifié (`intervention.affectee`) |
| GET | `/machines/comparaison?ids=1,2&type=VIBRATION` | tous | US-32 | statistiques par type (nb, moyenne, min, max, écart-type), série agrégée (~60 points) si `type`, alertes, indicateurs |
| PATCH | `/machines/:id/cout` | D, R | US-34 | `{ coutHoraireArret }` |
| GET | `/machines/:id/mesures-horaires` | tous | US-40 | moyennes horaires des mesures archivées (`from`, `to`, `type`) |
| PATCH | `/capteurs/:id/calibration` | R, T | US-39 | `{ gain?, offset? }` ou `{ gain?, valeurReference }` (la valeur actuelle devient la référence, ex. 0 A moteur arrêté). Appliquée aux mesures suivantes : `valeur = gain × brute + offset` |
| POST | `/capteurs/:id/remplacer` | R | US-37 | `{ identifiant? }` : l'ancien capteur est retiré (historique conservé, alertes ouvertes clôturées), le nouveau reçoit les mesures. Identifiant par défaut `<ancien>-R2`, `-R3`… |
| GET / POST | `/interventions/:id/photos` | tous / R, T | US-25 | multipart, champ `photo` (JPEG ou PNG vérifié sur le contenu, 5 Mo, 10 par intervention), `legende` facultative |
| GET | `/interventions/:id/photos/:photoId/fichier` | tous | US-25 | image (JWT requis ; le technicien : seulement ses interventions) |
| DELETE | `/interventions/:id/photos/:photoId` | R, T | US-25 | le technicien ne supprime que ses photos |
| GET | `/indicateurs/pannes?grain=week\|month` | D, R | US-16 | `series: [{ periode, nbPannes, tempsArretH, dureeMoyenneH, coutArret }]` |
| GET | `/indicateurs`, `/indicateurs/dashboard` | D, R | US-15, 33, 34 | en plus : `coutArret`, `frequencePannes30j`, `dureeMoyennePanneH`, `topArrets` (dashboard) |
| GET | `/rapports/maintenance?format=json\|csv\|html` | D, R | US-17 | période `from`/`to` ou `periode=mois-precedent\|semaine-precedente`. Aussi `npm run rapport` (cron) |
| POST | `/responsables/:id/reinitialiser-mot-de-passe` | D | US-35 | renvoie `motDePasseProvisoire` une seule fois, ferme toutes les sessions |
| POST | `/techniciens/:id/reinitialiser-mot-de-passe` | R | US-35 | idem |
| PATCH | `/responsables/:id/statut`, `/techniciens/:id/statut` | D / R | US-36 | (existant) la désactivation ferme aussi le flux temps réel ouvert (`session.revoquee`) |
| GET / PUT | `/notifications/canaux`, `/notifications/canaux/:canal` | D | US-38 | canaux `APP` et `EMAIL` : `{ actif, niveauMin: ALERTE\|CRITIQUE, destinataires }` |
| GET | `/firmware/versions` | D, R | US-46 | versions publiées par `npm run firmware:publier` |
| GET / POST | `/machines/:id/firmware` | D, R / R | US-46 | historique des déploiements / `{ version }` lance la mise à jour de la carte |
| GET | `/firmware/telechargement/:jeton/:fichier` | carte (sans JWT) | US-46 | jeton de déploiement à usage limité (30 min, invalidé à la fin) |

## 5. Temps réel (Server-Sent Events)

```js
const es = new EventSource(`${API}/stream?token=${accessToken}`);
es.addEventListener('mesure.recue', (e) => console.log(JSON.parse(e.data)));
es.addEventListener('machine.etat', (e) => { /* { machineId, code, etat } */ });
es.addEventListener('alerte.creee', (e) => { /* alerte complète */ });
```

| Événement | Destinataires | Contenu |
|---|---|---|
| `mesure.recue` | tous | `{ machineId, codeMachine, capteurId, type, valeur, unite, horodatage }` |
| `machine.etat` | tous | `{ machineId, code, etat }` |
| `capteur.etat` | D, R, T | `{ machineId, enLigne, ... }` : une fois par machine quand la carte se déconnecte, n'envoie plus rien depuis 60 s (heure de **réception**) ou revient |
| `alerte.creee` / `alerte.maj` | D, R, T | alerte |
| `intervention.maj` | D, R + technicien concerné | intervention |
| `intervention.affectee` | D, R + technicien affecté | intervention (notification PB-34) |
| `capteur.calibre` / `capteur.remplace` | R, T / tous | capteur (US-39, US-37) |
| `firmware.maj` | D, R | déploiement de firmware (US-46) |
| `session.revoquee` | utilisateur concerné | le compte a été désactivé ou son mot de passe réinitialisé : le serveur ferme le flux (US-36) |

`alerte.creee` et `alerte.maj` portent `notifier: true|false` (US-38) : afficher une notification seulement si `notifier` vaut `true`.

Quand l'accessToken expire, fermez l'EventSource et rouvrez-le avec le nouveau jeton.
Mobile : utilisez une bibliothèque SSE (ex. `react-native-sse`) ou rafraîchissez par appel périodique.

## 6. Dates
Toutes les dates sont au format ISO 8601 en UTC (`2026-10-14T15:00:00.000Z`). Les filtres `from` et `to` acceptent ce format.
