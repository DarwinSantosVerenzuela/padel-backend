# ============================================
# PadelApp Backend — Production Dockerfile
# Multi-stage build for minimal image size
# ============================================

# --- Stage 1: Build ---
FROM node:24-alpine AS builder

WORKDIR /app

# Copy dependency manifests first (cache layer)
COPY package.json package-lock.json* ./

# Install all dependencies (including devDeps for build)
RUN npm ci --ignore-scripts

# Copy source code
COPY tsconfig.json ./
COPY src/ ./src/

# Build TypeScript
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# --- Stage 2: Production ---
FROM node:24-alpine AS runner

# Security: run as non-root user
RUN addgroup --system --gid 1001 padel && \
    adduser --system --uid 1001 padel

WORKDIR /app

# Copy only production artifacts
COPY --from=builder --chown=padel:padel /app/dist ./dist
COPY --from=builder --chown=padel:padel /app/node_modules ./node_modules
COPY --from=builder --chown=padel:padel /app/package.json ./

# Environment variables are injected at runtime, NOT baked into image
ENV NODE_ENV=production
ENV PORT=4000

EXPOSE 4000

# Run as non-root
USER padel

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1

CMD ["node", "dist/server.js"]
