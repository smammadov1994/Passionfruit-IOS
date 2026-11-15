# syntax=docker/dockerfile:1
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
COPY data ./data
COPY migrations ./migrations
# Public certificate authorities (Supabase's database CA, Apple Root CA - G3). The APNs .p8 key
# is a secret: mount it, never copy it in.
COPY certs ./certs
RUN mkdir -p /app/certs /app/uploads && chown -R node:node /app
USER node
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# Migrations run automatically at startup when DATABASE_URL is set.
CMD ["node", "dist/index.js"]
