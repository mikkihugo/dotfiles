FROM docker:dind

RUN apk add --no-cache \
    bash \
    curl \
    unzip

# Install cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared && \
    chmod +x /usr/local/bin/cloudflared

# Install Vault
RUN curl -L https://releases.hashicorp.com/vault/1.15.2/vault_1.15.2_linux_amd64.zip \
    -o vault.zip && \
    unzip vault.zip && \
    mv vault /usr/local/bin/ && \
    rm vault.zip && \
    chmod +x /usr/local/bin/vault

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 2376 80 443

CMD ["/start.sh"]