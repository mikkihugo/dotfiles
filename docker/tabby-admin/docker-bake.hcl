group "nexus" {
  targets = ["ai-dev", "vault"]
}

target "ai-dev" {
  dockerfile = "ai-dev/Dockerfile.all-in-one"
  context = "ai-dev"
  tags = ["nexus-ai:latest"]
  cache-from = ["type=gha"]
  cache-to = ["type=gha,mode=max"]
  platforms = ["linux/amd64"]
}

target "vault" {
  context = "."
  dockerfile-inline = <<EOF
FROM vault:latest
COPY vault/config.hcl /vault/config/config.hcl
EOF
  tags = ["nexus-vault:latest"]
}

target "quick" {
  dockerfile = "ai-dev/Dockerfile.all-in-one"
  context = "ai-dev"
  tags = ["nexus-ai:latest"]
  # Use local cache for faster builds
  cache-from = ["type=local,src=/tmp/.buildx-cache"]
  cache-to = ["type=local,dest=/tmp/.buildx-cache"]
}