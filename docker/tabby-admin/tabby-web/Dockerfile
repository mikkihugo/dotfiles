FROM node:18-alpine

# Install dependencies
RUN apk add --no-cache \
    sqlite \
    openssh-client \
    git \
    curl

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install app dependencies
RUN npm ci --only=production

# Copy app source
COPY . .

# Create data directory
RUN mkdir -p /data

# Expose port
EXPOSE 9090

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9090/health || exit 1

# Run as non-root
USER node

# Start app
CMD ["node", "server.js"]