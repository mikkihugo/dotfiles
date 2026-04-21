package main

import (
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/mikkihugo/dotfiles/tools/machine-agent/internal/service"
)

// dispatch decodes an inbound protobuf frame, runs the requested RPC,
// and returns an encoded response frame.
// TODO: replace []byte framing with generated protobuf once proto is compiled.
func dispatch(ctx context.Context, frame []byte) ([]byte, error) {
	// Placeholder until protobuf codegen is wired in.
	// Frame format for now: "<method> <arg1> <arg2>"
	parts := strings.Fields(string(frame))
	if len(parts) == 0 {
		return nil, fmt.Errorf("empty frame")
	}

	switch parts[0] {
	case "ServiceExec":
		if len(parts) < 3 {
			return []byte("error: ServiceExec requires name action"), nil
		}
		name, action := parts[1], parts[2]
		if err := service.Validate(name); err != nil {
			return []byte("error: " + err.Error()), nil
		}
		switch action {
		case "start", "stop", "restart":
		default:
			return []byte("error: action must be start, stop, or restart"), nil
		}
		out, err := exec.CommandContext(ctx, "systemctl", "--user", action, name).CombinedOutput()
		if err != nil {
			return []byte("error: " + err.Error() + "\n" + string(out)), nil
		}
		return out, nil

	case "ServiceStatus":
		if len(parts) < 2 {
			return []byte("error: ServiceStatus requires name"), nil
		}
		if err := service.Validate(parts[1]); err != nil {
			return []byte("error: " + err.Error()), nil
		}
		out, _ := exec.CommandContext(ctx, "systemctl", "--user", "status", parts[1]).CombinedOutput()
		return out, nil

	case "ServiceLogs":
		if len(parts) < 2 {
			return []byte("error: ServiceLogs requires name"), nil
		}
		if err := service.Validate(parts[1]); err != nil {
			return []byte("error: " + err.Error()), nil
		}
		lines := "50"
		if len(parts) >= 3 {
			lines = parts[2]
		}
		out, _ := exec.CommandContext(ctx, "journalctl", "--user", "-u", parts[1], "-n", lines, "--no-pager").CombinedOutput()
		return out, nil

	case "AgentVersion":
		return []byte(fmt.Sprintf("version=%s commit=%s built=%s", version, commit, builtAt)), nil

	default:
		return []byte("error: unknown method " + parts[0]), nil
	}
}
