#!/bin/bash
# Bash-based fallback guardian when Rust is unavailable
# This is a simplified version of the Rust guardian that works on any system

# Log file for crash detection
LOG_FILE="$HOME/.shell-guardian.log"
CRASH_THRESHOLD=3
CRASH_TIME=10

# Get timestamp
timestamp() {
  date +%s
}

# Check if we're in a crash pattern
is_crash_pattern() {
  # Create log file if it doesn't exist
  touch "$LOG_FILE"
  
  # Get recent timestamps (last 3 lines)
  recent_timestamps=$(tail -n $CRASH_THRESHOLD "$LOG_FILE" 2>/dev/null)
  current_time=$(timestamp)
  crash_count=0
  
  # Process each timestamp
  while read -r line; do
    # Skip non-numeric lines
    if [[ "$line" =~ ^[0-9]+$ ]]; then
      time_diff=$((current_time - line))
      if [ "$time_diff" -lt "$CRASH_TIME" ]; then
        crash_count=$((crash_count + 1))
      fi
    fi
  done <<< "$recent_timestamps"
  
  # Check if we've reached the threshold
  if [ "$crash_count" -ge $((CRASH_THRESHOLD - 1)) ]; then
    # Log crash detection
    echo "CRASH_DETECTED_$(timestamp)" > "$LOG_FILE"
    return 0
  else
    return 1
  fi
}

# Run failsafe shell
run_failsafe_shell() {
  echo -e "\033[31m⚠️  Shell crash detected!\033[0m"
  echo -e "\033[33m💡 Launching minimal environment\033[0m"
  
  # Launch minimal bash
  SHELL_GUARDIAN_ACTIVE=1 \
  PS1="\[\033[31m\][FAILSAFE]\[\033[0m\] \w \$ " \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin" \
  TERM="xterm-256color" \
  bash --norc
  
  # Exit with the status of the failsafe shell
  exit $?
}

# Main function
main() {
  # Check args
  if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [args...]"
    exit 1
  fi
  
  # Check for crash pattern
  if is_crash_pattern; then
    run_failsafe_shell
  else
    # Log startup
    echo "$(timestamp)" >> "$LOG_FILE"
    
    # Run the requested shell
    command="$1"
    shift
    exec "$command" "$@"
  fi
}

# Run main function
main "$@"