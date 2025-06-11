FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    vim \
    openssh-client \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Install aider
RUN pip install --no-cache-dir aider-chat

# Install additional AI tools
RUN pip install --no-cache-dir \
    openai \
    anthropic \
    litellm \
    langchain

# Create workspace
WORKDIR /workspace

# Add startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["aider", "--architect"]