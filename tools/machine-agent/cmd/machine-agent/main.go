package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/mikkihugo/dotfiles/tools/machine-agent/internal/tunnel"
)

var (
	version = "dev"
	commit  = "none"
	builtAt = "unknown"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

	cfg := tunnel.Config{
		GatewayURL: env("MACHINE_AGENT_GATEWAY", "wss://llm-gateway.centralcloud.com/worker"),
		Token:      mustEnv("MACHINE_AGENT_TOKEN"),
		Hostname:   hostname(),
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	slog.Info("machine-agent starting", "version", version, "commit", commit, "hostname", cfg.Hostname)

	if err := tunnel.Run(ctx, cfg, dispatch); err != nil && err != context.Canceled {
		slog.Error("tunnel exited", "err", err)
		os.Exit(1)
	}
}

func hostname() string {
	h, _ := os.Hostname()
	return h
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		slog.Error("required env var missing", "key", key)
		os.Exit(1)
	}
	return v
}
