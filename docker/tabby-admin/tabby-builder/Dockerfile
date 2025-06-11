FROM node:18 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    make \
    g++ \
    rpm \
    zip

# Clone Tabby source
ARG TABBY_VERSION=v1.0.197
RUN git clone --depth 1 --branch ${TABBY_VERSION} \
    https://github.com/Eugeny/tabby.git /tabby

WORKDIR /tabby

# Install dependencies
RUN yarn install --frozen-lockfile

# Copy our custom configs
COPY configs/ /configs/

# Build script that embeds our config
COPY build-custom.js /build-custom.js

# Build for all platforms
RUN node /build-custom.js

# Output stage
FROM alpine:latest
COPY --from=builder /tabby/dist/* /output/

CMD ["ls", "-la", "/output/"]