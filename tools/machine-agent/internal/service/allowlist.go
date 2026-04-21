package service

import "fmt"

// allowlist is the hard-coded set of systemd units this agent may touch.
// Never read from config — the list is part of the binary.
var allowlist = map[string]bool{
	"openclaw-node":         true,
	"hermes-proxy":          true,
	"dotfiles-auto-update":  true,
	"machine-agent":         true,
}

// Validate returns an error if name is not in the allowlist.
func Validate(name string) error {
	if !allowlist[name] {
		return fmt.Errorf("unit %q not in allowlist", name)
	}
	return nil
}
