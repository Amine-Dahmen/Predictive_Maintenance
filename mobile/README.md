# Application mobile Flutter

Application mobile de maintenance prédictive IoT, située à côté de `backend`,
`frontend` et `docs`.

## Architecture MVVM

- `lib/models/` : rôles, techniciens et modèles d’affichage ;
- `lib/viewmodels/` : état et actions des écrans ;
- `lib/services/` : client HTTP, authentification JWT et appels API ;
- `lib/views/` : pages Flutter organisées par fonctionnalité ;
- `lib/config/` : configuration de l’API ;
- `lib/app.dart` : thème et composition de l’application ;
- `lib/main.dart` : point d’entrée minimal.

## Prérequis

Flutter **3.50 ou plus récent** (Gradle 9.5, Android Gradle Plugin 9.3.1). Avec une version
plus ancienne de Flutter, mettez Flutter à jour (`flutter upgrade`).

## Adresse du serveur (à lire en premier)

L’application parle au backend sur `http://<IP_DU_PC>:3000/api`. **L’adresse se règle dans
l’application** : écran de connexion → ligne **« Serveur : … » → Modifier**. Saisissez
seulement l’IP du PC (ex. `192.168.45.116`, le port 3000 et `/api` sont ajoutés), touchez
**Tester** (doit afficher « Connexion réussie »), puis **Enregistrer**. L’adresse reste
enregistrée sur le téléphone : **quand l’IP du PC change, on la corrige là, sans recompiler.**

- Adresse par défaut d’une nouvelle installation : `http://192.168.45.116:3000/api` (PC sur le
  point d’accès « BHK » du téléphone, novembre 2026), ou celle passée à la compilation avec
  `--dart-define=API_BASE_URL=...`. Bouton « Par défaut » pour y revenir.
- Trouver l’IP du PC : `ip -4 addr` (Linux, ligne `inet` de l’interface Wi-Fi, ex. `wlo1`) ou
  `ipconfig` (Windows, « Adresse IPv4 » de la carte Wi-Fi). Avec le téléphone en point d’accès,
  c’est l’adresse donnée par le téléphone au PC (même réseau que l’ESP32).
- Test rapide depuis le navigateur du téléphone : `http://<IP_DU_PC>:3000/api/health` doit
  afficher `{"statut":"ok",...}`. Sinon : backend arrêté, mauvaise IP, ou pare-feu du PC
  (`sudo ufw allow 3000/tcp`, ou règle entrante du pare-feu Windows pour le port 3000).

### Téléphone en point d’accès (configuration du projet)

Le téléphone partage sa connexion (point d’accès), le PC et l’ESP32 s’y connectent. Le
téléphone lui-même joint le PC par l’adresse que le point d’accès a donnée au PC : c’est
cette IP qu’il faut mettre dans « Serveur ». Le téléphone peut rester connecté à un autre Wi-Fi
en même temps (partage Wi-Fi) : l’adresse du PC sur le point d’accès reste valable. Elle peut
changer quand le PC se reconnecte : vérifiez-la avec `ip -4 addr` après chaque reconnexion.

## Installer l’application sur le téléphone

Prérequis côté PC : Flutter 3.50+ (`flutter doctor`) et le SDK Android.

```bash
cd mobile
flutter pub get
flutter build apk --release          # build/app/outputs/flutter-apk/app-release.apk
```

Trois façons de l’installer :

1. **Câble USB** (débogage USB activé dans les options développeur, accepter l’invite) :
   `adb install -r build/app/outputs/flutter-apk/app-release.apk`
2. **Sans câble, par le réseau** : sur le PC
   `python3 -m http.server 8099 --directory build/app/outputs/flutter-apk`, puis sur le
   téléphone ouvrir `http://<IP_DU_PC>:8099/app-release.apk` dans le navigateur et installer
   (autoriser l’installation depuis le navigateur la première fois). Arrêter le serveur après.
3. **Développement** (rechargement à chaud) : `flutter run` avec le téléphone branché.

L’APK est signée avec la clé de débogage (`android/app/build.gradle.kts`) : une nouvelle version
s’installe par-dessus l’ancienne et garde l’adresse du serveur enregistrée.

Cas particuliers :

- téléphone branché en USB sur n’importe quel réseau : `adb reverse tcp:3000 tcp:3000` puis
  Serveur = `127.0.0.1` ;
- émulateur Android : Serveur = `10.0.2.2` ;
- cible desktop : `flutter run -d linux` avec Serveur = `localhost`.

### Windows : chemin avec accents

Android Gradle et le compilateur de shaders Flutter peuvent échouer lorsque
le projet se trouve dans un chemin contenant des caractères non ASCII. Si
cette erreur apparaît, déplacez le projet dans un chemin court sans accents.

```powershell
cd C:\maintenance-pr-dictive-iot\mobile
flutter run
```

Le contrat REST est documenté dans `../backend/docs/API.md` et
`../backend/src/docs/openapi.json`.

La connexion appelle `POST /api/auth/login`. Après authentification, la
gestion des techniciens utilise directement le backend :

- `GET /api/techniciens` ;
- `POST /api/techniciens` ;
- `PATCH /api/techniciens/{id}` ;
- `PATCH /api/techniciens/{id}/statut`.

Aucun technicien n’est enregistré localement dans l’application mobile.

## Rôles dans l’application (backlog)

| Action | Technicien | Responsable |
|---|---|---|
| Prendre en compte une alerte (US-03) | oui | oui |
| Clôturer une alerte, fausse alerte (US-30, US-31) | non | oui |
| Planifier une intervention depuis une alerte (US-13) | non | oui |
| Déclarer une panne (US-29) | oui, sur une machine en panne : la réparation lui est affectée (« Prendre en charge la panne ») | oui (réparation affectée tout de suite ou plus tard) |
| Affecter / réaffecter (US-14) | se prendre une intervention non affectée (« À prendre » → « Prendre en charge »), extension hors backlog | oui (Interventions ou fiche machine) |
| Démarrer, compte rendu, photos, clôturer (US-06, US-07, US-25, US-26) | oui, ses interventions | non (consultation) |
| Calibrer un capteur (US-39) | oui | oui |
| Seuils, remplacement de capteur, firmware, comparaison (US-11, US-37, US-46, US-32) | non | oui |

**Une panne se termine quand le technicien clôture la réparation avec « Machine remise en service »**
(ce qui clôture aussi les alertes de la machine). La fiche machine montre la réparation en cours et qui
doit agir.

Les pages ouvertes se rechargent d’elles-mêmes quand le serveur annonce un changement (état d’une
machine, alerte, intervention, capteur, prédiction) ou quand le flux temps réel se reconnecte : l’état
affiché est le même que sur le site web.

## Parcours mobiles connectés

- Responsable : alertes (filtres, prise en compte et clôture commentée),
  machines (capteurs, mesures, historique, seuils), tableau de bord par état,
  planification/affectation/annulation des interventions et gestion des
  techniciens.
- Directeur : consultation du parc et des interventions, gestion des comptes
  responsables et attribution de leur rôle.
- Technicien : alertes, état des machines, démarrage des interventions,
  compte rendu brouillon et clôture avec résultat.
- Les données sont actualisées périodiquement. Le flux SSE relaie en temps réel
  les alertes, affectations et changements d’état pendant que l’application est
  ouverte. Les jetons JWT sont renouvelés automatiquement après expiration.

Les notifications système lorsque l’application est en arrière-plan nécessitent
un fournisseur push (par exemple Firebase Cloud Messaging/APNs) et une
configuration serveur qui ne sont pas présents dans ce dépôt. Le flux actuel
affiche des notifications dans l’application au premier plan.
