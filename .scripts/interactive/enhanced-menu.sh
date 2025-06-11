#!/bin/bash

# Enhanced SSH/Session Menu
# Combines tmux sessions with SSH connections from tabby-sync

set -e

# Enhanced menu with SSH + tmux
show_enhanced_menu() {
    local force="$1"
    
    # Debug info (comment out in production)
    # echo "DEBUG: Interactive: $-"
    # echo "DEBUG: TMUX: $TMUX"
    # echo "DEBUG: MENU_ENABLED: $MENU_ENABLED"
    
    # Exit if not interactive (unless forced)
    if [ "$force" != "force" ]; then
        [[ $- != *i* ]] && return
        
        # Only skip if we're actually inside a tmux pane (not just inherited TMUX var)
        if [ ! -z "$TMUX" ] && [ ! -z "$TMUX_PANE" ]; then
            return
        fi
        
        # Skip if disabled
        [ "${MENU_ENABLED}" = "false" ] && return
    fi
    
    # Smart menu selection based on environment
    # Use basic menu for SSH sessions or when BASIC_MENU is set
    if [ ! -z "$SSH_CONNECTION" ] || [ "$BASIC_MENU" = "true" ]; then
        # SSH session or forced basic - use number-based menu
        show_basic_menu
    elif command -v gum &>/dev/null && tty >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        # Local terminal with gum - use fancy menu
        show_gum_menu
    else
        # Fallback to basic menu
        show_basic_menu
    fi
}

# Gum-powered menu
show_gum_menu() {
    local options=()
    local header="🚀 SESSION & CONNECTION MANAGER"
    
    # Add tmux sessions with better formatting and numbers
    local sessions=$(tmux list-sessions -F "#{session_name}:#{?session_attached,[ATTACHED],[FREE]}:#{session_windows}w:#{session_created_string}" 2>/dev/null)
    if [ ! -z "$sessions" ]; then
        options+=("📋 TMUX SESSIONS")
        local i=1
        while IFS= read -r session; do
            local name=$(echo "$session" | cut -d: -f1)
            local status=$(echo "$session" | cut -d: -f2)
            local windows=$(echo "$session" | cut -d: -f3)
            local created=$(echo "$session" | cut -d: -f4)
            if [[ "$status" == "[ATTACHED]" ]]; then
                options+=("$i) 🟢 $name $status $windows")
            else
                options+=("$i) 🔵 $name $status $windows")
            fi
            ((i++))
        done <<< "$sessions"
        options+=("")
    fi
    
    # Add SSH hosts from tabby-sync
    if [ -f "$HOME/.tabby-hosts.json" ]; then
        local ssh_count=$(jq -r '.hosts | length' "$HOME/.tabby-hosts.json" 2>/dev/null || echo "0")
        if [ "$ssh_count" -gt 0 ]; then
            options+=("🌐 SSH CONNECTIONS ($ssh_count hosts)")
            jq -r '.hosts[] | "  🔗 \(.alias) → \(.user)@\(.hostname)"' "$HOME/.tabby-hosts.json" 2>/dev/null | head -10 | while read -r host; do
                options+=("$host")
            done
            options+=("")
        fi
    fi
    
    # Add Claude sessions
    options+=(
        "🤖 CLAUDE SESSIONS"
        "  🚀 Singularity Engine (Claude)"
        "  🏗️  Architect MCP (Claude)"
        ""
    )
    
    # Add actions
    options+=(
        "✨ New tmux session"
        "🗑️  Kill tmux session"
        "🐚 Plain bash shell"
        "💾 Restore tmux sessions"
        "🔄 Sync SSH hosts"
        "📦 Sync dotfiles"
        "⚙️  Quick tools"
        "🧹 Clear screen"
        "❌ Exit"
    )
    
    local choice=$(printf '%s\n' "${options[@]}" | gum choose \
        --header "$header" \
        --header.foreground="212" \
        --cursor.foreground="212" \
        --selected.foreground="212" \
        --height=20 \
        --cursor-prefix="▸ ")
    
    handle_choice "$choice"
}

# Handle menu choice
handle_choice() {
    local choice="$1"
    
    case "$choice" in
        "  🚀 Singularity Engine (Claude)")
            handle_claude_session "singularity-engine" "/home/mhugo/singularity-engine"
            ;;
        "  🏗️  Architect MCP (Claude)")
            handle_claude_session "architect-mcp" "/home/mhugo/architect-mcp"
            ;;
        [0-9]")"*)
            # Attach to tmux session by number
            local session_name=$(echo "$choice" | awk '{print $3}')
            tmux attach-session -t "$session_name"
            exit
            ;;
        "  🔗 "*)
            # SSH connection
            local alias=$(echo "$choice" | sed 's/.*🔗 \([^ ]*\) →.*/\1/')
            echo "🔗 Connecting to $alias..."
            ssh "$alias"
            ;;
        "✨ New tmux session")
            local name=$(gum input --placeholder "Session name" --header "New TMUX Session")
            if [ ! -z "$name" ]; then
                tmux new-session -s "$name"
                exit
            fi
            ;;
        "🗑️  Kill tmux session")
            local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
            if [ ! -z "$sessions" ]; then
                local session=$(echo "$sessions" | gum choose --header "Select session to kill")
                if [ ! -z "$session" ]; then
                    tmux kill-session -t "$session"
                    echo "🗑️  Killed session: $session"
                    sleep 1
                fi
            fi
            show_gum_menu
            ;;
        "🐚 Plain bash shell")
            exec bash --login
            ;;
        "💾 Restore tmux sessions")
            ~/.dotfiles/.scripts/tmux-save-restore.sh restore
            ;;
        "🔄 Sync SSH hosts")
            echo "🔄 Syncing SSH hosts..."
            if command -v tabby-sync &>/dev/null; then
                if [ -z "$TABBY_GIST_ID" ] && [ -z "$UNIFIED_HOSTS_GIST_ID" ]; then
                    echo "❌ No TABBY_GIST_ID set in ~/.env_tokens"
                    echo "💡 Set TABBY_GIST_ID=your_gist_id in ~/.env_tokens"
                else
                    (tabby-sync pull) && echo "✅ Sync complete!" || echo "❌ Sync failed!"
                fi
            else
                echo "❌ tabby-sync not found"
            fi
            sleep 3
            show_gum_menu
            ;;
        "📦 Sync dotfiles")
            echo "📦 Syncing dotfiles..."
            if ~/.dotfiles/.scripts/quick-check.sh sync; then
                echo "✅ Dotfiles synced successfully!"
            else
                echo "❌ Sync failed!"
            fi
            sleep 2
            show_gum_menu
            ;;
        "⚙️  Quick tools")
            show_tools_menu
            ;;
        "🧹 Clear screen")
            clear
            show_gum_menu
            ;;
        "❌ Exit")
            exit 0
            ;;
        "")
            # Empty choice, show menu again
            show_gum_menu
            ;;
    esac
}

# Tools submenu
show_tools_menu() {
    local tools_options=(
        "📊 System info"
        "📁 File manager (ranger/lf)"
        "🔍 Find files (fzf)"
        "💾 Backup/Restore"
        "📝 Edit dotfiles"
        "🏠 Back to main menu"
    )
    
    local tool_choice=$(printf '%s\n' "${tools_options[@]}" | gum choose \
        --header "⚙️ QUICK TOOLS" \
        --height=8)
    
    case "$tool_choice" in
        "📊 System info"*)
            show_system_info
            ;;
        "📁 File manager"*)
            if command -v ranger &>/dev/null; then
                ranger
            elif command -v lf &>/dev/null; then
                lf
            else
                echo "No file manager found. Install: mise install ranger"
                read -p "Press Enter to continue..."
            fi
            show_gum_menu
            ;;
        "🔍 Find files"*)
            if command -v fzf &>/dev/null; then
                local file=$(find . -type f 2>/dev/null | fzf --preview 'bat --color=always {}' --height=50%)
                if [ ! -z "$file" ]; then
                    ${EDITOR:-nano} "$file"
                fi
            else
                echo "fzf not found. Install: mise install fzf"
                read -p "Press Enter to continue..."
            fi
            show_gum_menu
            ;;
        "💾 Backup/Restore")
            ~/.dotfiles/.scripts/backup-restore.sh menu
            show_tools_menu
            ;;
        "📝 Edit dotfiles")
            cd ~/.dotfiles
            ${EDITOR:-nano} .
            show_gum_menu
            ;;
        "🏠 Back to main menu")
            show_gum_menu
            ;;
    esac
}

# Retro-styled menu with ASCII art
show_basic_menu() {
    clear
    local cyan='\033[96m'
    local green='\033[92m'
    local yellow='\033[93m'
    local blue='\033[94m'
    local magenta='\033[95m'
    local red='\033[91m'
    local reset='\033[0m'
    local bold='\033[1m'
    local dim='\033[2m'
    
    echo -e "${cyan}${bold}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║  ████████ ███    ███ ██    ██ ██   ██     ██   ██ ██    ██  ║"
    echo "║     ██    ████  ████ ██    ██  ██ ██      ██   ██ ██    ██  ║"
    echo "║     ██    ██ ████ ██ ██    ██   ███       ███████ ██    ██  ║"
    echo "║     ██    ██  ██  ██ ██    ██  ██ ██      ██   ██ ██    ██  ║"
    echo "║     ██    ██      ██  ██████  ██   ██     ██   ██  ██████   ║"
    echo "║                                                              ║"
    echo "║                ${yellow}⚡ RETRO SESSION MANAGER ⚡${cyan}                ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${reset}"
    
    echo -e "${green}${bold}┌─[ ${yellow}ACTIVE SESSIONS${green} ]────────────────────────────────────────┐${reset}"
    
    # Show numbered sessions with proper parsing
    local sessions_data=$(tmux list-sessions -F "#{session_name}|#{?session_attached,[ATTACHED],[FREE]}|#{session_windows}w" 2>/dev/null)
    local sessions=()
    if [ ! -z "$sessions_data" ]; then
        local i=1
        while IFS='|' read -r name status windows; do
            sessions+=("$name")
            if [[ "$status" == "[ATTACHED]" ]]; then
                echo -e "${green}│ ${bold}[${yellow}$i${green}]${reset} ${red}●${reset} ${bold}$name${reset} ${dim}$status $windows${reset}"
            else
                echo -e "${green}│ ${bold}[${yellow}$i${green}]${reset} ${blue}○${reset} ${bold}$name${reset} ${dim}$status $windows${reset}"
            fi
            ((i++))
        done <<< "$sessions_data"
    else
        echo -e "${green}│ ${dim}No active sessions${reset}"
    fi
    
    echo -e "${green}└────────────────────────────────────────────────────────────┘${reset}"
    echo ""
    echo -e "${magenta}${bold}┌─[ ${yellow}COMMAND CENTER${magenta} ]─────────────────────────────────────────┐${reset}"
    echo -e "${magenta}│                                                            │${reset}"
    echo -e "${magenta}│ ${yellow}[c1]${reset} ${cyan}Claude: Singularity${reset}  ${yellow}[c2]${reset} ${cyan}Claude: Architect${reset}          │${reset}"
    echo -e "${magenta}│ ${yellow}[n]${reset} ${cyan}New Session${reset}     ${yellow}[k]${reset} ${cyan}Kill Session${reset}     ${yellow}[i]${reset} ${cyan}System Info${reset}    │${reset}"
    echo -e "${magenta}│ ${yellow}[s]${reset} ${cyan}Shell${reset}           ${yellow}[b]${reset} ${cyan}Backup/Restore${reset}   ${yellow}[d]${reset} ${cyan}System Deps${reset}    │${reset}"
    echo -e "${magenta}│                                            ${yellow}[x]${reset} ${cyan}Exit${reset}           │${reset}"
    echo -e "${magenta}│                                                            │${reset}"
    echo -e "${magenta}└────────────────────────────────────────────────────────────┘${reset}"
    echo ""
    echo -e "${bold}${yellow}>>> ${reset}${dim}Enter your choice: ${reset}"
    read choice
    
    # Handle numbered choices (1-9 for sessions)
    if [[ "$choice" =~ ^[1-9]$ ]] && [ -n "${sessions[$((choice-1))]}" ]; then
        local session="${sessions[$((choice-1))]}"
        tmux attach -t "$session" 2>/dev/null || echo "Session not found"
        exit
    fi
    
    case $choice in
        c1)
            handle_claude_session "singularity-engine" "/home/mhugo/singularity-engine"
            exit
            ;;
        c2)
            handle_claude_session "architect-mcp" "/home/mhugo/architect-mcp"
            exit
            ;;
        n)
            echo -e "\n${green}${bold}╔═[ CREATE NEW SESSION ]══════════════════════════════════════╗${reset}"
            echo -e "${green}║                                                            ║${reset}"
            echo -e "${green}╚═════════════════════════════════════════════════════════════╝${reset}"
            echo -e "${yellow}>>> ${reset}${dim}Session name: ${reset}"
            read name
            if [ -n "$name" ]; then
                echo -e "${green}${bold}⚡ LAUNCHING:${reset} $name"
                tmux new-session -s "$name"
            fi
            exit
            ;;
        k)
            if [ ${#sessions[@]} -gt 0 ]; then
                echo -e "\n${red}${bold}╔═[ TERMINATE SESSION ]═══════════════════════════════════════╗${reset}"
                for i in "${!sessions[@]}"; do
                    echo -e "${red}║ ${yellow}[$((i+1))]${reset} ${sessions[$i]}${reset}"
                done
                echo -e "${red}╚═════════════════════════════════════════════════════════════╝${reset}"
                echo -e "${yellow}>>> ${reset}${dim}Session number to terminate: ${reset}"
                read num
                if [[ "$num" =~ ^[1-9]$ ]] && [ -n "${sessions[$((num-1))]}" ]; then
                    tmux kill-session -t "${sessions[$((num-1))]}"
                    echo -e "${red}${bold}⚡ TERMINATED:${reset} ${sessions[$((num-1))]}"
                    sleep 1
                fi
            fi
            show_basic_menu
            ;;
        s)
            exec bash --login
            ;;
        b)
            ~/.dotfiles/.scripts/backup-restore.sh menu
            show_basic_menu
            ;;
        i)
            show_system_info
            ;;
        d)
            echo -e "\n${yellow}${bold}╔═[ SYSTEM DEPENDENCIES ]═════════════════════════════════════╗${reset}"
            echo -e "${yellow}║ Installing system packages (tmux, curl, git, build tools)  ║${reset}"
            echo -e "${yellow}╚═════════════════════════════════════════════════════════════╝${reset}"
            ~/.dotfiles/.scripts/install-system-deps.sh
            read -p "Press Enter to continue..."
            show_basic_menu
            ;;
        x)
            exit 0
            ;;
        *)
            show_basic_menu
            ;;
    esac
}

# Auto-run if sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_enhanced_menu "$1"
fi

# System info display
show_system_info() {
    clear
    echo "🖥️  SYSTEM INFORMATION"
    echo "===================="
    echo ""
    
    # Basic system info
    echo "📋 System:"
    echo "  Host: $(hostname)"
    echo "  OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo "  Uptime: $(uptime -p 2>/dev/null || uptime | cut -d, -f1 | cut -d' ' -f3-)"
    echo ""
    
    # Memory info
    echo "💾 Memory:"
    free -h | awk 'NR==2{printf "  Used: %s/%s (%.0f%%)\n", $3,$2,$3*100/$2}'
    echo ""
    
    # Disk info
    echo "💿 Disk:"
    df -h / | awk 'NR==2{printf "  Root: %s/%s (%s used)\n", $3,$2,$5}'
    if [ -d /home ] && df /home >/dev/null 2>&1; then
        df -h /home | awk 'NR==2{printf "  Home: %s/%s (%s used)\n", $3,$2,$5}'
    fi
    echo ""
    
    # CPU info
    echo "⚡ CPU:"
    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ */  /'
        echo "  Cores: $(nproc) | Load: $(uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | sed 's/^ *//')"
    fi
    echo ""
    
    # Network info
    echo "🌐 Network:"
    if command -v ip >/dev/null 2>&1; then
        ip route get 1 2>/dev/null | awk '{print "  IP: " $7; exit}'
    fi
    if command -v curl >/dev/null 2>&1; then
        echo "  External: $(curl -s --max-time 3 https://ipinfo.io/ip 2>/dev/null || echo 'Unable to fetch')"
    fi
    echo ""
    
    # Tmux sessions
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
        echo "📋 Tmux Sessions:"
        tmux list-sessions -F "  #{session_name}: #{session_windows} windows #{?session_attached,(attached),(detached)}"
        echo ""
    fi
    
    # Quick system status
    echo "🚦 Quick Status:"
    if command -v systemctl >/dev/null 2>&1; then
        failed_services=$(systemctl --failed --no-legend | wc -l)
        echo "  Failed services: $failed_services"
    fi
    echo "  Last login: $(last -n 1 $USER 2>/dev/null | head -1 | awk '{print $4, $5, $6}' || echo 'Unknown')"
    
    echo ""
    if command -v gum &>/dev/null; then
        gum choose "📊 Open htop/btop" "🔄 Refresh" "🏠 Back to menu" | case "$(cat)" in
            "📊 Open htop/btop")
                if command -v btop &>/dev/null; then
                    btop
                elif command -v htop &>/dev/null; then
                    htop
                else
                    top
                fi
                ;;
            "🔄 Refresh")
                show_system_info
                return
                ;;
        esac
    else
        read -p "Press Enter to continue..."
    fi
    
    show_tools_menu
}

# Handle Claude sessions with proper tmux/worktree management
handle_claude_session() {
    local session_name="$1"
    local project_path="$2"
    
    # Check if directory exists
    if [ ! -d "$project_path" ]; then
        echo "❌ Directory not found: $project_path"
        read -p "Press Enter to continue..."
        show_gum_menu
        return
    fi
    
    # Create or attach to tmux session
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "📋 Attaching to existing session: $session_name"
        tmux attach-session -t "$session_name"
    else
        echo "✨ Creating new session: $session_name"
        # Create new tmux session and run Claude with session name
        tmux new-session -s "$session_name" -c "$project_path" \
            "echo '🤖 Starting Claude session: $session_name' && \
             echo '📁 Working directory: $project_path' && \
             echo '' && \
             claude --name '$session_name' || \
             handle_claude_exit '$project_path' '$session_name'"
    fi
}

# Handle Claude exit with git worktree safety checks
handle_claude_exit() {
    local project_path="$1"
    local session_name="$2"
    
    cd "$project_path"
    
    # Check if we're in a git worktree
    if git rev-parse --git-dir >/dev/null 2>&1 && [ -f "$(git rev-parse --git-dir)/gitdir" ]; then
        echo ""
        echo "🌳 Git worktree detected!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Check git status
        local has_changes=false
        local has_unpushed=false
        
        if ! git diff --quiet || ! git diff --cached --quiet; then
            has_changes=true
        fi
        
        if [ "$(git rev-list @{u}..HEAD 2>/dev/null | wc -l)" -gt 0 ]; then
            has_unpushed=true
        fi
        
        if [ "$has_changes" = true ] || [ "$has_unpushed" = true ]; then
            echo "⚠️  WARNING: Uncommitted changes or unpushed commits detected!"
            git status --short
            echo ""
            echo "🛑 Cannot safely remove worktree. Options:"
            echo "  1) Return to Claude to commit/push changes"
            echo "  2) Drop to bash shell to handle manually"
            echo "  3) Force remove (LOSES ALL WORK!)"
            echo ""
            read -p "Choose [1/2/3]: " choice
            
            case $choice in
                1)
                    claude --name "$session_name"
                    handle_claude_exit "$project_path" "$session_name"
                    ;;
                2)
                    echo "🐚 Dropping to bash. Type 'exit' when done."
                    bash
                    handle_claude_exit "$project_path" "$session_name"
                    ;;
                3)
                    echo "⚠️  Type YES to force remove and LOSE ALL WORK:"
                    read confirm
                    if [ "$confirm" = "YES" ]; then
                        cd ..
                        git worktree remove --force "$project_path"
                        echo "💥 Worktree forcefully removed!"
                        sleep 2
                    else
                        echo "❌ Aborted"
                        handle_claude_exit "$project_path" "$session_name"
                    fi
                    ;;
                *)
                    handle_claude_exit "$project_path" "$session_name"
                    ;;
            esac
        else
            # All clean, safe to remove
            echo "✅ Worktree is clean!"
            echo "🗑️  Safe to remove worktree? [y/N]:"
            read -p "" remove_choice
            if [[ "$remove_choice" =~ ^[Yy]$ ]]; then
                cd ..
                git worktree remove "$project_path"
                echo "✅ Worktree removed successfully!"
                sleep 2
            fi
        fi
    else
        echo ""
        echo "📋 Claude session ended: $session_name"
        echo "Options:"
        echo "  1) Restart Claude"
        echo "  2) Drop to bash shell"
        echo "  3) Exit tmux session"
        echo ""
        read -p "Choose [1/2/3]: " exit_choice
        
        case $exit_choice in
            1)
                claude --name "$session_name"
                handle_claude_exit "$project_path" "$session_name"
                ;;
            2)
                echo "🐚 Dropping to bash. Type 'exit' to close session."
                bash
                ;;
            3)
                exit
                ;;
            *)
                exit
                ;;
        esac
    fi
}

# Export for sourcing
export -f show_enhanced_menu show_system_info handle_claude_session handle_claude_exit