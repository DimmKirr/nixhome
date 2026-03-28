# Ghostty shell integration for zsh. This should be at the top of your zshrc!
if [ -n "$GHOSTTY_RESOURCES_DIR" ]; then
    builtin source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi

# Env Vars
export EDITOR='nvim'
export NIX_BUILD_SHELL=$SHELL
# Terraform local repo (for dev providers)
export TF_CLI_CONFIG_FILE=${HOME}/.terraformrc


# Separate history per each tmux session
if [[ -n "$TMUX" ]]; then
  export TMUX_SESSION_NAME=$(tmux display-message -p '#S')

  # History per session (project)
  export HISTFILE="$HOME/.zsh_history_$TMUX_SESSION_NAME"

  # Construct the dynamic variable name based on the value of TMUX
  dynamic_jira_token_var="JIRA_API_TOKEN_$TMUX_SESSION_NAME"

  # Check if this dynamically named variable is set and not empty
  # using Zsh's parameter indirection
  if [[ -n "${(P)dynamic_jira_token_var}" ]]; then
    # If it is set, you can access its value also using parameter indirection
    local token_value="${(P)dynamic_jira_token_var}"
    echo "JIRA token for TMUX_SESSION_NAME session '$TMUX_SESSION_NAME' ($dynamic_jira_token_var) is set to: $token_value"
    # You can now use $token_value
    export JIRA_API_TOKEN="$token_value"
  fi

  # Set JIRA_CONFIG (will be used in jira() function)
  export JIRA_CONFIG="$HOME/.config/.jira/.config-$TMUX_SESSION_NAME.yml"

else
  export HISTFILE="$HOME/.zsh_history"
  export JIRA_CONFIG="$HOME/.config/.jira/.config.yml"
fi

fpath+=($HOME/.local/share/zsh/site-functions)
fpath+=($HOME/.rbenv/completions)



# Login to 11password
# eval $(op signin)

# TODO: Possibly replace this by nix-native solution
#ize gen completion zsh > $HOME/.nix-profile/share/zsh/site-functions/_ize && chmod +rx $HOME/.nix-profile/share/zsh/site-functions/_ize

# TODO: Move to 1Password https://samedwardes.com/blog/2023-11-28-1password-for-secret-dotfiles-update/
source "/Volumes/SecureVault/profile/kireevco.rc"

# Custom PATH for tools developed that require to be accessed globally
# export PATH="$HOME/dev/automationd/atun/bin:$PATH" # disabled and managed in home manager main.

# Add brew to path just in case. Needs to be done after
# eval "$(/opt/homebrew/bin/brew shellenv)" # disabled since it brings /usr/local/bin first.


# Keys Bindings
bindkey  "^[[1~"  beginning-of-line
bindkey  "^[[4~"  end-of-line
bindkey  "^[[3~"  delete-char
bindkey  "^[[5~"  history-search-backward  # Page Up
bindkey  "^[[6~"  history-search-forward   # Page Down

#### Helper Functions
# Simple tool to perform continious http requests
function httping() {
  if [ -z "$1" ]; then
    echo "Error: No URL specified"
    return 1
  fi

  while true;
  do
    curl -o /dev/null --trace-time -s -w '[%{http_code}] %{time_total}s\n' $1 | ets --format "[%H:%M:%S]" && sleep 1
  done
}

pgping() {
    local HOST="$1"
    local PORT="5432"
    local TIMEOUT=3

    if [ -z "$HOST" ]; then
        echo "Usage: pgping <hostname>"
        return 1
    fi

    echo "Monitoring PostgreSQL connection to ${HOST}:${PORT}"
    echo "Press Ctrl+C to stop"
    echo "----------------------------------------"

    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        # Try to connect using pg_isready (fastest and most reliable)
        if command -v pg_isready &> /dev/null; then
            timeout ${TIMEOUT} pg_isready -h "${HOST}" -p "${PORT}" &> /dev/null
            RESULT=$?

            # pg_isready returns 0 if accepting connections, 1 if rejecting, 2 if no response/timeout
            if [ $RESULT -eq 0 ] || [ $RESULT -eq 1 ]; then
                echo "${TIMESTAMP} - OK"
            else
                echo "${TIMESTAMP} - ERROR (no response/timeout)"
            fi
        else
            # Fallback: use psql if pg_isready not available
            timeout ${TIMEOUT} psql -h "${HOST}" -p "${PORT}" -U postgres -d postgres -c "SELECT 1" &> /dev/null
            RESULT=$?

            # Exit codes: 0 = success, 1-2 = auth failure (but server responded), 124 = timeout, others = connection error
            if [ $RESULT -eq 0 ] || [ $RESULT -eq 1 ] || [ $RESULT -eq 2 ]; then
                echo "${TIMESTAMP} - OK (server responding)"
            elif [ $RESULT -eq 124 ]; then
                echo "${TIMESTAMP} - ERROR (timeout)"
            else
                echo "${TIMESTAMP} - ERROR (connection failed)"
            fi
        fi

        sleep 1
    done
}


function jira() {
  if [ -n "$JIRA_CONFIG" ]; then
    # JIRA_CONFIG is set, use it with --config
    command jira --config "${JIRA_CONFIG}" "$@"
  else
    # JIRA_CONFIG is not set, call jira normally
    command jira "$@"
  fi
}

# Simple function to post updates to WIP social network
function wip (){
    body=$(echo $1 | jq -R .)
    data="{ \"body\" =  $body }"
    resp=$(curl -s -q --request POST \
        --url "https://api.wip.co/v1/todos?api_key=${WIP_API_KEY}" \
        --header 'Content-Type: application/json' \
        --data $data > /dev/null
    )
    # check curl exit code
    if [ $? -ne 0 ]; then
        echo "Error: curl failed"
        return 1
    fi

    echo "OK"
}



function video_split() {
  video_name="$1"
  base_name="${video_name%.*}"

  ffmpeg -i "$video_name" \
    -vf "scale=-2:720" \
    -af "volume=2" \
    -c:v libx264 -crf 28 -preset fast \
    -c:a aac -b:a 128k \
    -f segment -segment_time 300 -reset_timestamps 1 \
    "%03d-${base_name}.mp4"
}

function video_increase_audio() {
  video_name="$1"
  volume_level="${2:-2}"


  base_name="${video_name%.*}"

  ffmpeg -i "$video_name" \
    -af "volume=$volume_level" \
    -c:v libx264 -crf 28 -preset fast \
    "${base_name}.mp4"
}


function split_video() {
  video_split $1
}

function video_messenger() {
  video_name="$1"
  base_name="${video_name%.*}"

  ffmpeg -i "$video_name" \
    -vf "scale=-2:720" \
    -af "volume=1.5" \
    -c:v libx264 -crf 28 -preset fast \
    -c:a aac -b:a 128k \
    "${base_name}.mp4"
}



function video_export_audio() {
  video_name="$1"
  base_name="${video_name%.*}"

  ffmpeg -i "$video_name" \
    -vn -acodec copy \
    "${base_name}.m4a"
}


function schedule_command() {
  # Example usage:
  # 1. Schedule a command to run at 20:00 UTC in session "WORK" window 3, pane 1:
  #    schedule_command "WORK:3" 1 "20:00" "echo 'Daily backup starting'"
  #
  # 2. Schedule a database maintenance task at midnight UTC:
  #    schedule_command "DB:1" 0 "00:00" "pg_repack -d mydb -t large_table"
  #
  # 3. Schedule a reminder in the current session:
  #    schedule_command "$(tmux display-message -p '#{session_name}'):$(tmux display-message -p '#{window_index}')" "$(tmux display-message -p '#{pane_index}')" "15:30" "echo 'Time for the team meeting!'"

  session_window="$1"  # Format: "SESSION:WINDOW" (e.g., "KIRR:3")
  window_index="$2"    # The window index (e.g., 1, 2, 3, etc.)
  target_time="$3"     # Format: "HH:MM" in UTC (e.g., "20:00" or "00:00")
  command="$4"         # The command to execute

  # Get the pane ID for the specified window index
  pane_id=$(tmux list-panes -t "$session_window" | grep "^$window_index:" | awk '{print $1}' | sed 's/[^0-9%]//g')

  if [ -z "$pane_id" ]; then
    echo "Error: Could not find pane with index $window_index in $session_window"
    return 1
  fi

  # Get current time components in UTC
  current_hour=$(date -u +"%H")
  current_minute=$(date -u +"%M")
  current_second=$(date -u +"%S")
  current_date=$(date -u +"%Y-%m-%d")

  # Extract hours and minutes from target time
  target_hour=${target_time%:*}
  target_minute=${target_time#*:}

  # Calculate current and target time in seconds since midnight
  current_seconds_since_midnight=$(( 10#$current_hour * 3600 + 10#$current_minute * 60 + 10#$current_second ))
  target_seconds_since_midnight=$(( 10#$target_hour * 3600 + 10#$target_minute * 60 ))

  # Determine if the target time is today or tomorrow
  if (( current_seconds_since_midnight >= target_seconds_since_midnight )); then
    # If current time is past the target time, schedule for tomorrow
    # On macOS, use -v for date adjustment
    target_date=$(date -u -d "tomorrow" +"%Y-%m-%d")
    delay=$(( 86400 - current_seconds_since_midnight + target_seconds_since_midnight ))
  else
    # Schedule for today
    target_date="$current_date"
    delay=$(( target_seconds_since_midnight - current_seconds_since_midnight ))
  fi

  # Sleep for the calculated delay in seconds
  (sleep "$delay" && tmux send-keys -t "$pane_id" "$command" && tmux send-keys -t "$pane_id" ENTER) &

  echo "Command scheduled to run at $target_time UTC on $target_date (in $delay seconds) on pane $pane_id (window index $window_index)"
}

listening() {
    if [ $# -eq 0 ]; then
        sudo lsof -iTCP -sTCP:LISTEN -n -P
    elif [ $# -eq 1 ]; then
        sudo lsof -iTCP -sTCP:LISTEN -n -P | grep -i --color $1
    else
        echo "Usage: listening [pattern]"
    fi
}

tmuxp-kill() {
    # If no arguments provided, default to current session
    if [ $# -eq 0 ]; then
        if [ -n "$TMUX_SESSION_NAME" ]; then
            set -- "$TMUX_SESSION_NAME"
            echo "No session specified, using current session: $TMUX_SESSION_NAME"
            echo ""
        else
            echo "Usage: tmuxp-kill <session1> [session2] [session3] ..."
            echo "Example: tmuxp-kill NPT MAP HZL"
            echo "Or run without arguments from within a tmux session to kill current session"
            return 1
        fi
    fi

    for session in "$@"; do
        echo "Processing session: $session"

        # Freeze (save) the session to yaml
        if tmuxp freeze "$session" -y --force 2>/dev/null; then
            echo "  ✓ Frozen to ~/.config/tmuxp/$session.yaml"
        else
            echo "  ✗ Failed to freeze $session (session may not exist)"
            continue
        fi

        # Kill the session
        if tmux kill-session -t "$session" 2>/dev/null; then
            echo "  ✓ Killed session $session"
        else
            echo "  ✗ Failed to kill session $session"
        fi

        echo ""
    done
}

# Hubstaff aliases
alias hs="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI"
alias hs-map-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3497711"
alias hs-hzl-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3497760"
alias hs-npt-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3497712"
alias hs-home-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3727679"
alias hs-nmd-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3736729"
alias hs-stop="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI stop"
alias hs-status="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI status"

# Hubstaff toggle functions
_hs_toggle() {
    local project_id="$1"
    local hs_cli="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI"

    # Get current status
    local hs_status=$($hs_cli status 2>/dev/null)

    # Check if tracking is active
    if echo "$hs_status" | grep -q '"tracking":true'; then
        # Get active project ID
        local active_id=$(echo "$hs_status" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

        # If the requested project is already running, stop it
        if [ "$active_id" = "$project_id" ]; then
            $hs_cli stop
        else
            # Different project is running, start the requested one
            $hs_cli start_project "$project_id"
        fi
    else
        # Nothing is running, start the requested project
        $hs_cli start_project "$project_id"
    fi
}

hs-hzl-toggle() {
    _hs_toggle 3497760
}

hs-map-toggle() {
    _hs_toggle 3497711
}

hs-npt-toggle() {
    _hs_toggle 3497712
}

hs-home-toggle() {
    _hs_toggle 3727679
}

hs-nmd-toggle() {
    _hs_toggle 3736729
}

cleandocker() {
  if [[ "$1" == "-f" ]]; then
    # Full reset - delete VM disk
    docker desktop stop

    echo "Removing Docker VM disk..."
    rm -rf ~/Library/Containers/com.docker.docker/Data/vms/0/data
    docker desktop start

    echo "Docker is ready!"
  else
    # Soft cleanup
    echo "Removing Containers"
    docker rm -f $(docker ps -aq) 2>/dev/null || true

    echo "Pruning System"
    docker system prune -af

    echo "Pruning Volumes"
    docker volume prune -f
  fi
}


function _tmuxsave_inject_cell_ids() {
  local session="$1"
  local yaml="$HOME/.config/tmuxp/$session.yaml"

  [[ ! -f "$yaml" ]] && return

  local window_count wi
  window_count=$(yq '.windows | length' "$yaml")

  for ((wi=0; wi<window_count; wi++)); do
    local window_name
    window_name=$(yq ".windows[$wi].window_name" "$yaml")

    local pane_ids=()
    pane_ids=(${(f)"$(tmux list-panes -t "${session}:${window_name}" -F '#{pane_id}' 2>/dev/null | sed 's/^%//')"})
    [[ ${#pane_ids} -eq 0 ]] && continue

    local pane_count pi
    pane_count=$(yq ".windows[$wi].panes | length" "$yaml")

    for ((pi=0; pi<pane_count && pi<${#pane_ids}; pi++)); do
      local pane_id="${pane_ids[$((pi+1))]}"  # zsh arrays are 1-indexed
      local pane_tag
      pane_tag=$(yq ".windows[$wi].panes[$pi] | tag" "$yaml")

      if [[ "$pane_tag" == "!!str" ]]; then
        local shell_cmd
        shell_cmd=$(yq ".windows[$wi].panes[$pi]" "$yaml")
        SHELL_CMD="$shell_cmd" PANE_ID="$pane_id" \
          yq -i ".windows[$wi].panes[$pi] = {\"shell_command\": strenv(SHELL_CMD), \"environment\": {\"CELL_ID\": strenv(PANE_ID)}}" "$yaml"
      else
        local existing
        existing=$(yq ".windows[$wi].panes[$pi].environment.CELL_ID" "$yaml")
        if [[ "$existing" == "null" ]]; then
          PANE_ID="$pane_id" yq -i ".windows[$wi].panes[$pi].environment.CELL_ID = strenv(PANE_ID)" "$yaml"
        fi
      fi
    done
  done
}

function _tmuxsave_backup() {
  local session="$1"
  local src="$HOME/.config/tmuxp/$session.yaml"
  local backup_base="$HOME/.config/tmuxp/backups"
  local now
  now=$(date '+%Y-%m-%dT%H-%M-%S')

  [[ ! -f "$src" ]] && return

  python3 - "$session" "$src" "$backup_base" "$now" << 'EOF'
import sys, shutil
from datetime import datetime
from pathlib import Path

session, src, backup_base, now_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
now = datetime.strptime(now_str, '%Y-%m-%dT%H-%M-%S')

for tier in ['recent', 'daily', 'weekly', 'monthly']:
    Path(f'{backup_base}/{tier}').mkdir(parents=True, exist_ok=True)

filename = f'{session}-{now_str}.yaml'

def get_period(dt, tier):
    if tier == 'daily':   return dt.strftime('%Y-%m-%d')
    if tier == 'weekly':  return dt.strftime('%G-W%V')
    if tier == 'monthly': return dt.strftime('%Y-%m')
    return None

def parse_dt(f):
    stem = f.stem
    prefix = f'{session}-'
    if not stem.startswith(prefix):
        return None
    try:
        return datetime.strptime(stem[len(prefix):], '%Y-%m-%dT%H-%M-%S')
    except Exception:
        return None

limits = {'recent': 7, 'daily': 7, 'weekly': 4, 'monthly': 12}

for tier, limit in limits.items():
    tier_dir = Path(f'{backup_base}/{tier}')
    # For tiered saves: remove existing files from same period (keep only latest per period)
    if tier != 'recent':
        current_period = get_period(now, tier)
        for f in tier_dir.glob(f'{session}-*.yaml'):
            dt = parse_dt(f)
            if dt and get_period(dt, tier) == current_period:
                f.unlink()
    # Copy current save into this tier
    shutil.copy2(src, tier_dir / filename)
    # Rotate: drop oldest beyond limit
    files = sorted(tier_dir.glob(f'{session}-*.yaml'))
    for f in files[:-limit]:
        f.unlink()

pass
EOF
}

function _tmuxsave_strip_interpreters() {
  local yaml="$1"
  [[ ! -f "$yaml" ]] && return
  python3 - "$yaml" << 'EOF'
import sys, re
from pathlib import Path

yaml_path = Path(sys.argv[1])
text = yaml_path.read_text()

# Process names that should not be restored as commands (they open REPLs)
INTERPRETERS = {
  'python', 'python2', 'python3',
  'ipython', 'ipython3', 'bpython',
  'node', 'nodejs',
  'ruby', 'irb',
  'lua', 'luajit',
  'ghci', 'iex',
  'julia', 'R',
}

def is_interpreter(cmd):
  if not cmd:
    return False
  basename = cmd.strip().split('/')[-1]
  # strip version suffix: python3.12 -> python3 -> python
  name = re.split(r'[\.\d]', basename)[0]
  return basename in INTERPRETERS or name in INTERPRETERS

try:
  import yaml as pyyaml
except ImportError:
  # No PyYAML — fall back to regex line removal
  lines = []
  for line in text.splitlines():
    stripped = line.strip().lstrip('- ').strip()
    if is_interpreter(stripped):
      continue
    lines.append(line)
  yaml_path.write_text('\n'.join(lines) + '\n')
  sys.exit(0)

data = pyyaml.safe_load(text)

def clean_pane(pane):
  if isinstance(pane, str):
    return 'pane' if is_interpreter(pane) else pane
  if isinstance(pane, dict) and 'shell_command' in pane:
    cmds = pane['shell_command']
    if isinstance(cmds, str):
      if is_interpreter(cmds):
        del pane['shell_command']
    elif isinstance(cmds, list):
      pane['shell_command'] = [c for c in cmds if not is_interpreter(str(c))]
      if not pane['shell_command']:
        del pane['shell_command']
  return pane

for window in data.get('windows', []):
  window['panes'] = [clean_pane(p) for p in window.get('panes', [])]

yaml_path.write_text(pyyaml.dump(data, default_flow_style=False, allow_unicode=True))
EOF
}

function tmuxsave() {
  local session_list

  if [[ -n "$TMUX_SESSION_NAME" ]]; then
    session_list=("$TMUX_SESSION_NAME")
  else
    session_list=(${(f)"$(tmux list-sessions -F '#S' 2>/dev/null)"})
  fi

  for item in "${session_list[@]}"; do
    tmuxp freeze "$item" -y -q --force -o "~/.config/tmuxp/$item.yaml" &>/dev/null
    _tmuxsave_inject_cell_ids "$item" &>/dev/null
    _tmuxsave_strip_interpreters "$HOME/.config/tmuxp/$item.yaml" &>/dev/null
    _tmuxsave_backup "$item" && echo "[OK] $item.yaml"
  done
}

function tmuxload-dk() {
  for item in NMD DIMM KIRR; do
    tmuxp load "$item";
  done
}

function tmuxload-wk() {
  for item in NPT HZL; do
    tmuxp load "$item";
  done
}
#
# # Claude Wrappers
# _claude_with_profile() {
#   export CLAUDE_CONFIG_DIR="$1"
#   command claude "$@"
# }
#
# # # Personal profile (default)
# claude() {
#   _claude_with_profile "$HOME/.claude" "$@"
# }
#
# # Work profile
# claude-hzl() {
#   _claude_with_profile "$HOME/.claude-hzl" "$@"
# }
#

# Linear Issue Link Helpers (OSC 8 Hyperlinks for Ghostty)
# Usage: kut 178, core 1519, etc. to print clickable links
# Or pipe output: echo "Working on KUT-178" | linear-links

# Helper function for individual issue links
_linear_link() {
  local prefix="$1"
  local num="$2"
  local workspace="$3"
  printf '\e]8;;https://linear.app/%s/issue/%s-%s\e\\%s-%s\e]8;;\e\\\n' "$workspace" "$prefix" "$num" "$prefix" "$num"
}

# Individual project shortcuts
kut() { _linear_link "KUT" "$1" "hazelops" }
core() { _linear_link "CORE" "$1" "hazelops" }
kirr() { _linear_link "KIRR" "$1" "hazelops" }
tfk() { _linear_link "TFK" "$1" "hazelops" }
miska() { _linear_link "MISKA" "$1" "hazelops" }
upe() { _linear_link "UPE" "$1" "upeforge" }
nmd() { _linear_link "NMD" "$1" "hazelops" }

# Pipe-able function to convert all Linear patterns to clickable links
linear-links() {
  sed -E \
    -e 's/KUT-([0-9]+)/\x1b]8;;https:\/\/linear.app\/hazelops\/issue\/KUT-\1\x1b\\KUT-\1\x1b]8;;\x1b\\/g' \
    -e 's/CORE-([0-9]+)/\x1b]8;;https:\/\/linear.app\/hazelops\/issue\/CORE-\1\x1b\\CORE-\1\x1b]8;;\x1b\\/g' \
    -e 's/KIRR-([0-9]+)/\x1b]8;;https:\/\/linear.app\/hazelops\/issue\/KIRR-\1\x1b\\KIRR-\1\x1b]8;;\x1b\\/g' \
    -e 's/TFK-([0-9]+)/\x1b]8;;https:\/\/linear.app\/hazelops\/issue\/TFK-\1\x1b\\TFK-\1\x1b]8;;\x1b\\/g' \
    -e 's/MISKA-([0-9]+)/\x1b]8;;https:\/\/linear.app\/hazelops\/issue\/MISKA-\1\x1b\\MISKA-\1\x1b]8;;\x1b\\/g' \
    -e 's/UPE-([0-9]+)/\x1b]8;;https:\/\/linear.app\/upeforge\/issue\/UPE-\1\x1b\\UPE-\1\x1b]8;;\x1b\\/g' \
    -e 's/NMD-([0-9]+)/\x1b]8;;https:\/\/linear.app\/hazelops\/issue\/NMD-\1\x1b\\NMD-\1\x1b]8;;\x1b\\/g'
}

# Git log with clickable Linear issue links
git-linear() {
  git log --oneline --color=always "$@" | linear-links
}

# Jira Issue Link Helpers (OSC 8 Hyperlinks for Ghostty)
# Usage: npt 3122 to print clickable link
# Or pipe output: echo "Working on NPT-3122" | jira-links

# Helper function for Jira issue links
_jira_link() {
  local prefix="$1"
  local num="$2"
  local jira_url="$3"
  printf '\e]8;;%s/browse/%s-%s\e\\%s-%s\e]8;;\e\\\n' "$jira_url" "$prefix" "$num" "$prefix" "$num"
}

# Jira project shortcuts
npt() { _jira_link "NPT" "$1" "https://shiftlabny.atlassian.net" }

# Pipe-able function to convert Jira patterns to clickable links
jira-links() {
  sed -E \
    -e 's/NPT-([0-9]+)/\x1b]8;;https:\/\/shiftlabny.atlassian.net\/browse\/NPT-\1\x1b\\NPT-\1\x1b]8;;\x1b\\/g'
}

# Git log with clickable Jira issue links
git-jira() {
  git log --oneline --color=always "$@" | jira-links
}

# Combined Linear + Jira links
all-links() {
  linear-links | jira-links
}

git-all() {
  git log --oneline --color=always "$@" | all-links
}

# Use 1Password SSH agent
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
