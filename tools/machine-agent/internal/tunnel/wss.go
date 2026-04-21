// Package tunnel manages the outbound WSS reverse tunnel to the central gateway.
// The agent always connects out — no listening port, no inbound firewall rules.
package tunnel

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

const reconnectDelay = 10 * time.Second

type Config struct {
	GatewayURL string // wss://llm-gateway.centralcloud.com/worker
	Token      string // OpenBao AppRole token
	Hostname   string // this machine's name
}

// Run connects to the gateway and dispatches inbound RPC frames until ctx is cancelled.
// Reconnects automatically on disconnect.
func Run(ctx context.Context, cfg Config, dispatch func(ctx context.Context, frame []byte) ([]byte, error)) error {
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := connect(ctx, cfg, dispatch); err != nil {
			slog.Warn("tunnel disconnected, reconnecting", "err", err, "delay", reconnectDelay)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(reconnectDelay):
		}
	}
}

func connect(ctx context.Context, cfg Config, dispatch func(ctx context.Context, frame []byte) ([]byte, error)) error {
	hdr := http.Header{}
	hdr.Set("Authorization", "Bearer "+cfg.Token)
	hdr.Set("X-Agent-Hostname", cfg.Hostname)

	conn, _, err := websocket.DefaultDialer.DialContext(ctx, cfg.GatewayURL, hdr)
	if err != nil {
		return fmt.Errorf("dial: %w", err)
	}
	defer conn.Close()

	slog.Info("tunnel connected", "gateway", cfg.GatewayURL)

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			return fmt.Errorf("read: %w", err)
		}
		resp, err := dispatch(ctx, msg)
		if err != nil {
			slog.Warn("dispatch error", "err", err)
			continue
		}
		if err := conn.WriteMessage(websocket.BinaryMessage, resp); err != nil {
			return fmt.Errorf("write: %w", err)
		}
	}
}
