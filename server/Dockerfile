# syntax=docker/dockerfile:1

# ---- deps: install production dependencies only ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# Use the lockfile when present; fall back to install on first build.
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

# ---- runtime ----
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Run as the built-in unprivileged user.
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node package.json index.js imageRoute.js ./

USER node
EXPOSE 8080

# Container-level healthcheck hitting the /health route.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "index.js"]
