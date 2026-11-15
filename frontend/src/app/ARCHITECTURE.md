# Architecture de l'application

L'application suit une organisation MVC adaptée à Angular :

```text
src/app/
├── core/
│   ├── guards/          # Protection des routes
│   ├── interceptors/    # Traitement HTTP transversal
│   └── services/        # Services singleton et accès API
├── models/              # Interfaces et types du domaine
├── controllers/         # Facades et orchestration de la logique d'écran
├── views/
│   ├── pages/           # Composants associés aux routes
│   └── components/      # Composants propres à une fonctionnalité
├── shared/
│   ├── components/      # Composants réutilisables
│   ├── directives/      # Directives réutilisables
│   └── pipes/           # Pipes réutilisables
├── app.config.ts        # Configuration globale
├── app.routes.ts        # Déclaration des routes
└── app.ts               # Composant racine
```

## Règles de dépendance

- `models` ne dépend d'aucune couche Angular.
- `core` contient les services transversaux et ne dépend pas des vues.
- `controllers` orchestre les modèles et les services pour une page.
- `views` affiche les données et transmet les actions utilisateur au contrôleur.
- `shared` reste générique et ne contient aucune logique métier spécifique.
- Une fonctionnalité doit privilégier un contrôleur/facade plutôt que de placer la logique métier dans son template.
