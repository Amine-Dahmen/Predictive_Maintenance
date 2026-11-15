# API + passerelle MQTT. Au démarrage : migrations, compte directeur initial, serveur.
FROM node:26-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY src ./src
COPY scripts ./scripts
COPY docs ./docs
# Utilisateur sans privilèges ; seuls les photos (US-25) et les versions de firmware (US-46) sont écrits
RUN mkdir -p uploads firmware && chown -R node:node uploads firmware
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD wget -qO- http://127.0.0.1:3000/api/health || exit 1
CMD ["sh", "-c", "node src/db/migrate.js && node src/db/seed.js && node src/server.js"]
