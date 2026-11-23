# ABOUTME: Container image for the claim relayer, run once a day by a Kubernetes CronJob (see cd/).
# ABOUTME: Configuration comes from the environment (no .env in the image); the SQLite DB lives on a mounted volume.
FROM node:22-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee

WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

COPY lock.js relay.js store.js ./

# The official image's unprivileged user (uid 1000).
USER node

ENTRYPOINT ["node", "relay.js"]
