
# Multi-stage build for FiatRails API Service
FROM node:22-slim AS base

# Install dependencies only when needed
FROM base AS deps
WORKDIR /app

# Install build dependencies for native modules (better-sqlite3)
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci

# Production image
FROM base AS runner
WORKDIR /app

# No additional runtime dependencies needed for Debian

# Don't run as root
RUN groupadd --system --gid 1001 nodejs
RUN useradd --system --uid 1001 -g nodejs fiatrails

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY --chown=fiatrails:nodejs . .

# Create data directory for SQLite and DLQ with correct permissions
RUN mkdir -p /app/data && chown -R fiatrails:nodejs /app/data

# Switch to non-root user
USER fiatrails

# Expose API port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start the application
CMD ["node", "src/index.js"]
