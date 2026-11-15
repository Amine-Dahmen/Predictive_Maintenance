# Contrat MQTT — équipe embarquée (ESP32) ↔ backend

Ce document est la référence commune entre l'équipe embarquée et l'équipe backend.
Toute modification doit être validée par les deux équipes.

Implémentations :
- **carte ESP32** : firmware MicroPython dans [`partie_embarque/`](../../partie_embarque/README.md)
  (DHT22, SW-420, ACS712) ;
- **backend** : `src/mqtt/` (client, analyse des topics, traitement des mesures) ;
- **simulateur** : `scripts/simulateur-esp32.js` publie exactement les mêmes messages que la carte.

## 1. Connexion au broker

| Paramètre | Valeur |
|---|---|
| Broker | Mosquitto, adresse IP du PC/serveur backend |
| Port | `1883` (développement) — `8883` avec TLS (production) |
| Identifiant (username) | **le code de la machine**, ex. `M01` |
| Mot de passe | fourni par l'équipe backend (un par ESP32), créé avec `scripts/creer-utilisateurs-mqtt.*` |
| Client ID | `esp32-<code>`, ex. `esp32-M01` (unique) |
| Keep alive | 15 s |

Les connexions anonymes sont refusées. Un ESP32 ne peut publier **que** sous `usine/machines/<son code>/…`
(règle ACL du broker) : l'ESP32 `M01` ne peut pas envoyer de données pour `M02`.

## 2. Topics

| Topic | Sens | QoS | Retain | Contenu |
|---|---|---|---|---|
| `usine/machines/<code>/mesures` | ESP32 → backend | 1 | non | JSON des mesures (voir §3) |
| `usine/machines/<code>/statut` | ESP32 → backend | 1 | **oui** | `online` à la connexion, `offline` en **Last Will** |
| `usine/machines/<code>/config` | backend → ESP32 | 1 | **oui** | seuils de la machine (voir §3 bis) |
| `usine/backend/statut` | backend → ESP32 | 1 | oui | `online` / `offline` (facultatif à lire) |

## 3. Format du message de mesures

```json
{ "courant": 1.21, "vibration": 3.4, "temperature": 24.3, "humidite": 51.0, "ts": 1792745000 }
```

| Champ | Type | Unité | Capteur de la carte | Plage acceptée |
|---|---|---|---|---|
| `courant` | nombre | ampère (A), valeur efficace | ACS712 | 0 – 1000 |
| `vibration` | nombre | impulsions par seconde (imp/s) | SW-420 | 0 – 10 000 |
| `temperature` | nombre | °C | DHT22 | -40 – 80 |
| `humidite` | nombre | % d'humidité relative | DHT22 | 0 – 100 |
| `ts` | entier | secondes (ou millisecondes) depuis 1970, UTC | horloge NTP de l'ESP32 | facultatif |

Règles :
- **Nombres JSON**, pas de chaînes : `12.4` et non `"12.4"`.
- Au moins une mesure par message. Une mesure dont la lecture a échoué est envoyée à `null`
  (ex. DHT22 qui ne répond pas) : elle est ignorée, les autres sont traitées.
- `ts` est omis tant que l'ESP32 n'est pas synchronisé NTP : le backend utilise alors son heure.
  Une heure incohérente (plus de 5 min dans le futur ou plus de 24 h dans le passé) est aussi remplacée.
- Champs supplémentaires autorisés et ignorés par le backend ; la carte envoie `seq` (numéro du message),
  `uptime_s` et `alertes_locales` (alertes allumant la LED de la carte), utiles pour le débogage.
- Taille maximale du message : 4 Ko.
- Fréquence : **une publication toutes les 2 à 5 secondes** (5 s sur la carte).
- Le backend considère un capteur **inactif** s'il ne reçoit rien pendant **60 s** :
  la machine passe alors en gris « Sans données ».
- Une valeur hors plage est ignorée et signalée comme « mesure invalide ».
- La mesure n'est enregistrée que si la machine possède un capteur actif du type correspondant
  (déclaré dans l'application, ou créé automatiquement avec l'option « carte ESP32 PrédiMaint »).

## 3 bis. Seuils envoyés à la carte (US-11)

À chaque modification d'un seuil dans l'application (et pour toutes les machines au démarrage du backend),
le backend publie, en message retenu :

```json
{ "seuils": { "courant": { "alerte": 3, "critique": 4.5 }, "vibration": { "alerte": 20, "critique": 50 },
              "temperature": { "alerte": 45, "critique": 60 }, "humidite": { "alerte": 80, "critique": 90 } } }
```

Les noms de champs sont ceux du message de mesures. La carte reçoit ce message à chaque connexion et
allume sa LED au-dessus du seuil d'alerte. ACL : seul le backend écrit, chaque ESP32 ne lit que le sien.

## 3 ter. Perte du Wi-Fi (US-45)

Pendant une coupure du Wi-Fi ou du broker, la carte continue de mesurer et garde les messages en mémoire
(15 min par défaut, `BUFFER_SIZE`). À la reconnexion, elle les envoie du plus ancien au plus récent,
20 par cycle, avec leur `ts` d'origine : le backend les enregistre à leur vraie date. Le broker publie
`offline` (Last Will) dès que la carte disparaît : ses capteurs passent hors ligne et la machine
« Sans données » ; elle repasse en ligne à la reconnexion.

## 3 quater. Mise à jour du firmware à distance (US-46)

| Topic | Sens | Contenu |
|---|---|---|
| `usine/machines/<code>/ota` | backend → carte, QoS 1, non retenu | `{"version": "1.3.0", "deploiement": 12, "url": "http://<pc>:3000/api/firmware/telechargement/<jeton>", "fichiers": [{"nom": "main.py", "taille": 5120, "sha256": "…"}]}` |
| `usine/machines/<code>/ota/statut` | carte → backend, QoS 1 | `{"statut": "EN_COURS" \| "REUSSI" \| "ECHEC" \| "DEMARRE", "version", "deploiement", "message"}` |

- ACL : seul le backend écrit `.../ota`, seule la carte `<code>` le lit ; la carte écrit seulement son `.../ota/statut`.
- La carte télécharge chaque fichier (`<url>/<nom>`), vérifie taille et SHA-256 **avant** de remplacer quoi que ce soit,
  garde l'ancienne version en `.bak`, redémarre. `boot.py` revient à l'ancienne version après 3 démarrages sans
  confirmation ; `REUSSI` est publié une fois la nouvelle version connectée au broker.
- À chaque connexion la carte publie `{"statut": "DEMARRE", "version": "<FIRMWARE_VERSION>"}` : le backend affiche la
  version en service.
- Jamais envoyés : `credentials.py` (secrets Wi-Fi / MQTT) et `boot.py` (filet de sécurité).

## 4. Ce que fait le backend à la réception

1. Vérifie le format, la machine (`code`) et le capteur du type correspondant.
2. Enregistre la mesure dans PostgreSQL.
3. Compare la valeur aux seuils de la machine (seuil d'alerte / seuil critique, configurés dans l'application).
4. Crée une alerte si nécessaire et met à jour l'état de la machine (vert / orange / rouge).
5. Pousse la mesure et l'état en temps réel vers le front web et mobile.

## 5. Côté carte

Le firmware MicroPython (`partie_embarque/src/`) suit ce contrat : `net.py` gère la connexion, le Last Will
et la reconnexion, `main.py` construit le message toutes les 5 s. Le câblage des capteurs et la mise en
service sont décrits dans `partie_embarque/README.md`.

La carte allume aussi sa LED (GPIO2) quand une mesure dépasse un seuil local (`THRESHOLDS` dans
`partie_embarque/src/config.py`). C'est une indication sur place : les alertes de référence sont celles
du backend, visibles dans l'application.

## 6. Tester sans la carte

Le backend fournit un simulateur qui publie exactement ce format :

```bash
npm run simulateur                              # machine M01, valeurs normales
node scripts/simulateur-esp32.js M01 anomalie   # vibration, courant et température montent jusqu'à la panne
```

Pour écouter ce que publie une vraie carte :

```bash
mosquitto_sub -h <broker> -u backend -P <mot_de_passe> -t "usine/machines/#" -v
```
