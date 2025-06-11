#!/bin/bash
# Mise task to verify failsafe integrity
# This runs quietly in the background to avoid slowing down login

# Run the integrity check in the background with minimal output
nohup bash ~/.dotfiles/.scripts/verify-failsafe-integrity.sh > ~/.config/failsafe/last-check.log 2>&1 &