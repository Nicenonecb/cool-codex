#!/usr/bin/env bash
set -euo pipefail

program_name="$(basename "$0")"

usage() {
  cat <<'EOF'
Usage:
  cool-codex list
  cool-codex renderers
  cool-codex inspect <pid> [pid...]
  cool-codex kill-agent-renderers
  cool-codex kill-agent
  cool-codex kill-pids <pid> [pid...]
  cool-codex cooldown
  cool-codex cooldown-safe
  cool-codex cooldown-ui
  cool-codex cooldown-reduce-effects
  cool-codex cooldown-restore-effects
  cool-codex cooldown-watch
  coolcodex

What it does:
  list        Show Chrome-related processes and classify them.
  renderers   Find all Chrome Helper (Renderer) processes and classify them.
  inspect     Show full command and classification for specific PIDs.
  kill-agent-renderers
              Kill only renderer processes that look like Codex/agent-browser Chrome.
  kill-agent  Kill only processes that look like Codex/agent-browser Chrome.
  kill-pids   Kill only the given PIDs if they match Codex/agent-browser rules.
  cooldown    Diagnose current heat sources.
  cooldown-safe
              Kill automation Chrome processes, then restart lightweight UI agents.
  cooldown-ui Restart Dock, SystemUIServer, and ControlCenter.
  cooldown-reduce-effects
              Reduce transparency and motion to lower WindowServer work.
  cooldown-restore-effects
              Restore transparency and motion defaults.
  cooldown-watch
              Refresh heat-source diagnostics every 5 seconds.
  coolcodex    Shortcut for cool-codex cooldown-safe.

Safety:
  This script does not kill normal "Google Chrome Helper (Renderer)" processes
  unless the full command clearly contains Codex/agent-browser markers.
  Cooldown commands do not kill WindowServer, because that effectively logs you out.

Compatibility:
  chrome-process-guard is kept as a legacy alias for the same CLI.
EOF
}

is_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

get_command() {
  local pid="$1"
  ps -p "$pid" -o command= 2>/dev/null || true
}

print_process_header() {
  printf '%-8s %-32s %s\n' "PID" "CLASSIFICATION" "COMMAND"
  printf '%-8s %-32s %s\n' "---" "--------------" "-------"
}

classify_command() {
  local command="$1"

  if [[ "$command" == *"agent-browser-chrome"* ]]; then
    echo "CODEX_AGENT_BROWSER"
    return
  fi

  if [[ "$command" == *"/.agent-browser/browsers/"* ]]; then
    echo "CODEX_AGENT_BROWSER"
    return
  fi

  if [[ "$command" == *"Google Chrome for Testing"* && "$command" == *"--user-data-dir="*"/T/"* ]]; then
    echo "CHROME_FOR_TESTING_TEMP"
    return
  fi

  if [[ "$command" == *"Google Chrome for Testing"* && "$command" == *"--remote-debugging-port"* ]]; then
    echo "CHROME_FOR_TESTING_AUTOMATION"
    return
  fi

  if [[ "$command" == *"/Applications/Google Chrome.app/"* ]]; then
    echo "NORMAL_GOOGLE_CHROME"
    return
  fi

  if [[ "$command" == *"Google Chrome Helper"* || "$command" == *"Google Chrome for Testing"* ]]; then
    echo "UNKNOWN_CHROME_RELATED"
    return
  fi

  echo "NOT_CHROME_RELATED"
}

is_agent_browser_command() {
  local command="$1"
  local classification
  classification="$(classify_command "$command")"

  [[ "$classification" == "CODEX_AGENT_BROWSER" ||
     "$classification" == "CHROME_FOR_TESTING_TEMP" ||
     "$classification" == "CHROME_FOR_TESTING_AUTOMATION" ]]
}

chrome_pids() {
  pgrep -f "Google Chrome|Chrome for Testing|agent-browser-chrome" 2>/dev/null || true
}

renderer_pids() {
  pgrep -f "Google Chrome( for Testing)? Helper \\(Renderer\\)" 2>/dev/null || true
}

print_process() {
  local pid="$1"
  local command classification

  command="$(get_command "$pid")"
  if [[ -z "$command" ]]; then
    printf '%-8s %-32s %s\n' "$pid" "NOT_RUNNING" ""
    return
  fi

  classification="$(classify_command "$command")"
  printf '%-8s %-32s %s\n' "$pid" "$classification" "$command"
}

list_processes() {
  list_matching_processes chrome_pids "No Chrome-related processes found."
}

list_renderers() {
  list_matching_processes renderer_pids "No Chrome Helper (Renderer) processes found."
}

list_matching_processes() {
  local source_func="$1"
  local empty_message="$2"
  local found=0
  print_process_header

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    found=1
    print_process "$pid"
  done < <("$source_func")

  if [[ "$found" -eq 0 ]]; then
    echo "$empty_message"
  fi
}

inspect_pids() {
  if [[ "$#" -eq 0 ]]; then
    echo "Missing PID."
    usage
    exit 2
  fi

  print_process_header

  local pid
  for pid in "$@"; do
    if ! is_integer "$pid"; then
      printf '%-8s %-32s %s\n' "$pid" "INVALID_PID" ""
      continue
    fi
    print_process "$pid"
  done
}

terminate_pid() {
  local pid="$1"
  local command

  command="$(get_command "$pid")"
  if [[ -z "$command" ]]; then
    echo "PID $pid is not running."
    return
  fi

  if ! is_agent_browser_command "$command"; then
    echo "Skip PID $pid: not classified as Codex/agent-browser Chrome."
    return
  fi

  echo "Sending SIGTERM to PID $pid"
  kill -TERM "$pid" 2>/dev/null || true
}

force_kill_if_running() {
  local pid="$1"
  local command

  command="$(get_command "$pid")"
  if [[ -z "$command" ]]; then
    return
  fi

  if ! is_agent_browser_command "$command"; then
    echo "Skip SIGKILL for PID $pid: classification changed or not agent-browser."
    return
  fi

  echo "Sending SIGKILL to still-running PID $pid"
  kill -KILL "$pid" 2>/dev/null || true
}

kill_pids() {
  if [[ "$#" -eq 0 ]]; then
    echo "Missing PID."
    usage
    exit 2
  fi

  local pids=()
  local pid pid_count=0
  for pid in "$@"; do
    if ! is_integer "$pid"; then
      echo "Skip invalid PID: $pid"
      continue
    fi
    pids+=("$pid")
    pid_count=$((pid_count + 1))
    terminate_pid "$pid"
  done

  if [[ "$pid_count" -eq 0 ]]; then
    echo "Done."
    return
  fi

  sleep 2

  for pid in "${pids[@]}"; do
    force_kill_if_running "$pid"
  done

  echo "Done."
}

kill_agent_processes() {
  kill_agent_processes_from chrome_pids "No Codex/agent-browser Chrome processes found."
}

kill_agent_renderer_processes() {
  kill_agent_processes_from renderer_pids "No Codex/agent-browser Chrome renderer processes found."
}

kill_agent_processes_from() {
  local source_func="$1"
  local empty_message="$2"
  local pids=()
  local pid command pid_count=0

  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    command="$(get_command "$pid")"
    if [[ -n "$command" ]] && is_agent_browser_command "$command"; then
      pids+=("$pid")
      pid_count=$((pid_count + 1))
    fi
  done < <("$source_func")

  if [[ "$pid_count" -eq 0 ]]; then
    echo "$empty_message"
    return
  fi

  kill_pids "${pids[@]}"
}

headline() {
  printf '\n== %s ==\n' "$1"
}

top_cpu() {
  headline "Top CPU"
  ps -Ao pid,pcpu,pmem,comm | sort -k2 -nr | head -20 || true
}

windowserver_status() {
  headline "WindowServer"
  ps -Ao pid,pcpu,pmem,comm | awk '/WindowServer/ { print }'
}

spotlight_status() {
  headline "Spotlight indexing"
  ps -Ao pid,pcpu,pmem,comm \
    | awk '/\/mds$|\/mds_stores$|\/corespotlightd$|\/mdworker/ { print }' \
    | sort -k2 -nr \
    | head -12 \
    || true
}

browser_status() {
  headline "Browser / Web renderers"
  ps -Ao pid,pcpu,pmem,command \
    | awk '/Google Chrome|Chrome for Testing|WebKit.WebContent|Safari/ { print }' \
    | sort -k2 -nr \
    | head -20 \
    || true
}

cooldown_diagnose() {
  top_cpu
  windowserver_status
  browser_status
  spotlight_status
}

restart_ui_agents() {
  headline "Restarting lightweight UI agents"
  echo "Restarting Dock..."
  killall Dock 2>/dev/null || true

  echo "Restarting SystemUIServer..."
  killall SystemUIServer 2>/dev/null || true

  echo "Restarting ControlCenter..."
  killall ControlCenter 2>/dev/null || true

  echo "Done. These services should relaunch automatically."
}

cooldown_safe() {
  cooldown_diagnose
  kill_agent_processes
  restart_ui_agents
  sleep 2
  cooldown_diagnose
}

cooldown_reduce_effects() {
  headline "Reducing UI effects"
  defaults write com.apple.Accessibility ReduceMotionEnabled -bool true
  defaults write com.apple.universalaccess reduceTransparency -bool true
  restart_ui_agents
  echo "Reduced motion/transparency. Some apps may need reopening to fully pick this up."
}

cooldown_restore_effects() {
  headline "Restoring UI effects"
  defaults delete com.apple.Accessibility ReduceMotionEnabled 2>/dev/null || true
  defaults delete com.apple.universalaccess reduceTransparency 2>/dev/null || true
  restart_ui_agents
  echo "Restored motion/transparency defaults."
}

cooldown_watch() {
  while true; do
    clear
    date
    cooldown_diagnose
    sleep 5
  done
}

main() {
  local command="${1:-}"
  shift || true

  if [[ "$program_name" == "coolcodex" && -z "$command" ]]; then
    cooldown_safe
    return
  fi

  case "$command" in
    list)
      list_processes
      ;;
    renderers)
      list_renderers
      ;;
    inspect)
      inspect_pids "$@"
      ;;
    kill-agent-renderers)
      kill_agent_renderer_processes
      ;;
    kill-agent)
      kill_agent_processes
      ;;
    kill-pids)
      kill_pids "$@"
      ;;
    cooldown)
      cooldown_diagnose
      ;;
    cooldown-safe)
      cooldown_safe
      ;;
    cooldown-ui)
      restart_ui_agents
      ;;
    cooldown-reduce-effects)
      cooldown_reduce_effects
      ;;
    cooldown-restore-effects)
      cooldown_restore_effects
      ;;
    cooldown-watch)
      cooldown_watch
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "Unknown command: $command"
      usage
      exit 2
      ;;
  esac
}

main "$@"
