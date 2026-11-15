// Configuration de l'application Express (sans démarrage du serveur : utile pour les tests)
const express = require("express");
const helmet = require("helmet");
const cors = require("cors");
const env = require("./config/env");
const routes = require("./routes");
const { apiLimiter } = require("./middlewares/rateLimit");
const { notFound, errorHandler } = require("./middlewares/errorHandler");

const app = express();

app.disable("x-powered-by");
// Documentation interactive Swagger : http://localhost:3000/api/docs (désactivée en production)
if (!env.isProd) {
  const swaggerUi = require("swagger-ui-express");
  const openapi = require("./docs/openapi.json");
  app.get("/api/openapi.json", (req, res) => res.json(openapi));
  app.use(
    "/api/docs",
    swaggerUi.serve,
    swaggerUi.setup(openapi, {
      swaggerOptions: {
        persistAuthorization: true,
        displayRequestDuration: true,
      },
    }),
  );
}

app.set("trust proxy", 1); // nécessaire derrière un reverse proxy (nginx) pour le rate limiting par IP

// En-têtes de sécurité HTTP (CSP, HSTS, X-Frame-Options...)
app.use(helmet());

// CORS : seules les origines déclarées dans CORS_ORIGINS peuvent appeler l'API depuis un navigateur.
// Les applications mobiles natives n'envoient pas d'en-tête Origin et ne sont pas concernées.
app.use(
  cors({
    origin(origin, cb) {
      if (!origin || env.corsOrigins.includes(origin)) return cb(null, true);
      return cb(null, false);
    },
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE"],
    allowedHeaders: ["Content-Type", "Authorization"],
    maxAge: 600,
  }),
);

app.use(express.json({ limit: "100kb" }));
app.use("/api", apiLimiter, routes);

app.use(notFound);
app.use(errorHandler);

module.exports = app;
