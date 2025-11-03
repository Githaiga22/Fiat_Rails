
# Multi-stage build for FiatRails API Service
FROM node:22-alpine AS base

# Install dependencies only when needed
FROM base AS deps
WORKDIR /app

# Install build dependencies for native modules (better-sqlite3)
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    sqlite-dev

# Copy package files
COPY package.json package-lock.json* ./

# Install dependencies
RUN npm ci

# Production image
FROM base AS runner
WORKDIR /app

# Install runtime dependencies for better-sqlite3
RUN apk add --no-cache \
    libstdc++ \
    sqlite-libs

# Don't run as root
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 fiatrails

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY --chown=fiatrails:nodejs . .

# Switch to non-root user
USER fiatrails

# Expose API port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start the application
CMD ["node", "src/index.js"]
