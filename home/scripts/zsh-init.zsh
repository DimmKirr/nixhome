# Ghostty shell integration for zsh. This should be at the top of your zshrc!
if [ -n "$GHOSTTY_RESOURCES_DIR" ]; then
    builtin source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi

# Env Vars
export EDITOR='nvim'
export NIX_BUILD_SHELL=$SHELL
# Terraform local repo (for dev providers)
export TF_CLI_CONFIG_FILE=${HOME}/.terraformrc


# Separate history (and JIRA config) per multiplexer session.
# Works under tmux ($TMUX) or zellij ($ZELLIJ_SESSION_NAME); whichever is
# active provides the session name we key HISTFILE on, so command recall is
# scoped to the project. Same-named sessions share a file (e.g. tmux "NMD"
# and zellij "NMD" both use ~/.zsh_history_NMD). Falls back to global
# history outside both multiplexers.
local session_name=""
if [[ -n "$TMUX" ]]; then
  # Keep TMUX_SESSION_NAME exported — several helpers below depend on it.
  export TMUX_SESSION_NAME=$(tmux display-message -p '#S')
  session_name="$TMUX_SESSION_NAME"
elif [[ -n "$ZELLIJ_SESSION_NAME" ]]; then
  session_name="$ZELLIJ_SESSION_NAME"
fi

if [[ -n "$session_name" ]]; then
  # History per session (project)
  export HISTFILE="$HOME/.zsh_history_$session_name"

  # Construct the dynamic variable name based on the session name
  dynamic_jira_token_var="JIRA_API_TOKEN_$session_name"

  # Check if this dynamically named variable is set and not empty
  # using Zsh's parameter indirection
  if [[ -n "${(P)dynamic_jira_token_var}" ]]; then
    # If it is set, you can access its value also using parameter indirection
    local token_value="${(P)dynamic_jira_token_var}"
    echo "JIRA token for session '$session_name' ($dynamic_jira_token_var) is set to: $token_value"
    # You can now use $token_value
    export JIRA_API_TOKEN="$token_value"
  fi

  # Set JIRA_CONFIG (will be used in jira() function)
  export JIRA_CONFIG="$HOME/.config/.jira/.config-$session_name.yml"

else
  export HISTFILE="$HOME/.zsh_history"
  export JIRA_CONFIG="$HOME/.config/.jira/.config.yml"
fi

fpath+=($HOME/.local/share/zsh/site-functions)
fpath+=($HOME/.rbenv/completions)

# Dynamic completions — each binary generates its own zsh completions at shell
# startup, so we always match the installed version (no stale static scripts).
# sed strips any ANSI-decorated banner lines some Cobra CLIs print before the
# actual #compdef script (causes "bad pattern" errors in eval).
# Cobra's `completion zsh` emits `compdef _foo foo` at line 2, before the
# _foo() function body. Via fpath that's fine (lazy autoload), but eval runs
# it immediately → "function definition file not found". Strip it + any ANSI
# welcome banner, eval the body, then register compdef once _foo exists.
_dynamic_completion() {
  local out
  out="$("$1" ${@:2} 2>/dev/null)" || return
  out="$(printf '%s\n' "$out" | sed -n '/^#compdef/,$p' | sed '/^compdef /d')"
  eval "$out"
  compdef "_$1" "$1"
}
(( $+commands[cell] )) && _dynamic_completion cell completion zsh
(( $+commands[atun] )) && _dynamic_completion atun completion zsh



# Login to 11password
# eval $(op signin)

# TODO: Possibly replace this by nix-native solution
#ize gen completion zsh > $HOME/.nix-profile/share/zsh/site-functions/_ize && chmod +rx $HOME/.nix-profile/share/zsh/site-functions/_ize

# TODO: Move to 1Password https://samedwardes.com/blog/2023-11-28-1password-for-secret-dotfiles-update/
[ -f "/Volumes/SecureVault/profile/kireevco.rc" ] && source "/Volumes/SecureVault/profile/kireevco.rc"

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
alias hs-ever-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3956768"
alias hs-upe-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3956769"
alias hs-cell-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 4165404"
alias hs-dimm-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3956770"
alias hs-kirr-start="/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI start_project 3956771"
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

hs-ever-toggle() {
    _hs_toggle 3956768
}

hs-upe-toggle() {
    _hs_toggle 3956769
}

hs-cell-toggle() {
    _hs_toggle 4165404
}

hs-dimm-toggle() {
    _hs_toggle 3956770
}

hs-kirr-toggle() {
    _hs_toggle 3956771
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

    echo "Pruning Buildx Cache"
    docker buildx prune -af
  fi
}


function tmuxsave() {
  # Usage:
  #   tmuxsave        -> save ALL sessions + manifest
  #   tmuxsave .      -> save current session only (must be inside tmux)
  #   tmuxsave NAME   -> save the named session
  if [[ "$1" == "." ]]; then
    if [[ -z "$TMUX_SESSION_NAME" ]]; then
      echo "tmuxsave .: not inside tmux (TMUX_SESSION_NAME unset)" >&2
      return 1
    fi
    tmux-snapshot save "$TMUX_SESSION_NAME"
  elif [[ -n "$1" ]]; then
    tmux-snapshot save "$1"
  else
    tmux-snapshot save-all
  fi
}

function tmuxload-dk() {
  local manifest="$HOME/.config/tmuxp/.session-order"
  local -a sessions

  if [[ -f "$manifest" ]]; then
    # Load only sessions that belong to this group, preserving manifest order
    while IFS= read -r s; do
      [[ "$s" == NMD || "$s" == DIMM || "$s" == KIRR ]] && sessions+=("$s")
    done < "$manifest"
    # Fall back to default order if none found in manifest
    [[ ${#sessions[@]} -eq 0 ]] && sessions=(NMD DIMM KIRR)
  else
    sessions=(NMD DIMM KIRR)
  fi

  for item in "${sessions[@]}"; do
    tmux-snapshot load "$item"
  done
}

function tmuxload-wk() {
  local manifest="$HOME/.config/tmuxp/.session-order"
  local -a sessions

  if [[ -f "$manifest" ]]; then
    while IFS= read -r s; do
      [[ "$s" == NPT || "$s" == HZL ]] && sessions+=("$s")
    done < "$manifest"
    [[ ${#sessions[@]} -eq 0 ]] && sessions=(NPT HZL)
  else
    sessions=(NPT HZL)
  fi

  for item in "${sessions[@]}"; do
    tmux-snapshot load "$item"
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

# AI-powered git commit message generator (uses local Ollama)
aicommit() {
  local diff model prompt response

  diff=$(git diff --cached 2>/dev/null)
  if [[ -z "$diff" ]]; then
    echo "No staged changes. Stage files first with: git add <files>"
    return 1
  fi

  model="${AICOMMIT_MODEL:-llama3.2:3b}"

  prompt="Generate a single conventional commit message (type: subject) for this diff. Types: feat, fix, refactor, docs, chore, test, style, perf. Be concise. Output ONLY the commit message, nothing else.

${diff:0:8000}"

  response=$(curl -s --max-time 30 http://localhost:11434/api/generate \
    -d "$(jq -n \
      --arg model "$model" \
      --arg prompt "$prompt" \
      '{model: $model, prompt: $prompt, stream: false, options: {temperature: 0.3, num_predict: 100}}')" \
    2>/dev/null)

  if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
    echo "Error: Could not connect to Ollama at localhost:11434"
    echo "Make sure Ollama is running: ollama serve"
    return 1
  fi

  local msg
  msg=$(echo "$response" | jq -r '.response // empty' 2>/dev/null)

  if [[ -z "$msg" ]]; then
    echo "Error: No response from model"
    echo "$response" | jq -r '.error // "Unknown error"' 2>/dev/null
    return 1
  fi

  # Trim whitespace
  msg=$(echo "$msg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  echo "$msg"

  if [[ "$1" == "--commit" ]]; then
    git commit -m "$msg"
  else
    echo ""
    echo "Run 'aicommit --commit' to commit, or copy the message above."
  fi
}

# AI-powered grouped commit message generator (uses local Ollama)
# Analyzes all uncommitted changes, groups them by feature, and stores
# the plan in .git/commit-groups.json for review before committing.
#
# Usage:
#   aigroupcommit              # analyze changes and generate groups
#   aigroupcommit --show       # show current plan
#   aigroupcommit --commit     # commit each group in sequence
#   aigroupcommit --reset      # delete the plan
#   AICOMMIT_MODEL=qwen2:7b aigroupcommit  # use a different model
aigroupcommit() {
  local git_dir groups_file

  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "Error: not a git repository"
    return 1
  fi
  groups_file="$git_dir/commit-groups.json"

  # --reset: delete the plan
  if [[ "$1" == "--reset" ]]; then
    rm -f "$groups_file"
    echo "Plan deleted."
    return 0
  fi

  # --show: display current plan
  if [[ "$1" == "--show" ]]; then
    if [[ ! -f "$groups_file" ]]; then
      echo "No plan found. Run 'aigroupcommit' first."
      return 1
    fi
    local count
    count=$(jq length "$groups_file")
    echo "=== $count group(s) in plan ==="
    echo ""
    jq -r '.[] | "Group \(.id): \(.name)\n  Files: \(.files | join(", "))\n  Message: \(.message | split("\n") | .[0])\n"' "$groups_file"
    return 0
  fi

  # --commit: execute the plan
  if [[ "$1" == "--commit" ]]; then
    if [[ ! -f "$groups_file" ]]; then
      echo "No plan found. Run 'aigroupcommit' first."
      return 1
    fi

    local count committed skipped
    count=$(jq length "$groups_file")
    committed=0
    skipped=0

    for i in $(seq 0 $((count - 1))); do
      local group name files has_changes
      group=$(jq -r ".[$i]" "$groups_file")
      name=$(echo "$group" | jq -r '.name')
      echo "=== Group $((i+1))/$count: $name ==="

      git reset HEAD -- . 2>/dev/null || true

      has_changes=false
      while IFS= read -r f; do
        if git diff --quiet HEAD -- ":/$f" 2>/dev/null; then
          echo "  (skip) $f — already clean"
        else
          git add -- ":/$f"
          has_changes=true
        fi
      done < <(echo "$group" | jq -r '.files[]')

      if [[ "$has_changes" == "true" ]] && ! git diff --cached --quiet; then
        echo "$group" | jq -r '.message' | git commit -F -
        committed=$((committed + 1))
      else
        echo "  ⏭  All files already committed, skipping group."
        skipped=$((skipped + 1))
      fi
      echo ""
    done

    echo "Done: $committed committed, $skipped skipped (of $count groups)."
    rm -f "$groups_file"
    return 0
  fi

  # Default: analyze and generate groups
  local diff
  diff=$(git diff HEAD 2>/dev/null)
  if [[ -z "$diff" ]]; then
    echo "No uncommitted changes."
    return 1
  fi

  local model prompt response
  model="${AICOMMIT_MODEL:-llama3.2:3b}"

  # Get list of changed files for context
  local changed_files
  changed_files=$(git diff --name-only HEAD 2>/dev/null)

  prompt='Analyze this git diff and group the changes by feature. Return ONLY valid JSON, no explanation.

Output format — a JSON array:
[
  {
    "id": 1,
    "name": "Short feature name",
    "files": ["path/to/file1", "path/to/file2"],
    "message": "type(scope): one-line summary\n\n- type(scope): detail"
  }
]

Rules:
- Group related files that form a single logical change
- Use conventional commit types: feat, fix, refactor, docs, chore, test, style, perf
- Each file must appear in exactly one group
- Order groups by dependency (foundational first)
- Message first line under 72 chars

Changed files:
'"$changed_files"'

Diff (truncated to 8000 chars):
'"${diff:0:8000}"

  response=$(curl -s --max-time 60 http://localhost:11434/api/generate \
    -d "$(jq -n \
      --arg model "$model" \
      --arg prompt "$prompt" \
      '{model: $model, prompt: $prompt, stream: false, options: {temperature: 0.3, num_predict: 2000}}')" \
    2>/dev/null)

  if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
    echo "Error: Could not connect to Ollama at localhost:11434"
    return 1
  fi

  local raw_json
  raw_json=$(echo "$response" | jq -r '.response // empty' 2>/dev/null)

  if [[ -z "$raw_json" ]]; then
    echo "Error: No response from model"
    echo "$response" | jq -r '.error // "Unknown error"' 2>/dev/null
    return 1
  fi

  # Extract JSON array from response (model may wrap it in markdown fences)
  local clean_json
  clean_json=$(echo "$raw_json" | sed -n '/\[/,/\]/p' | head -100)

  # Validate JSON
  if ! echo "$clean_json" | jq '.' >/dev/null 2>&1; then
    echo "Error: Model returned invalid JSON. Raw response:"
    echo "$raw_json"
    return 1
  fi

  # Verify all changed files are covered
  local grouped_files missing
  grouped_files=$(echo "$clean_json" | jq -r '.[].files[]' | sort)
  missing=$(comm -23 <(echo "$changed_files" | sort) <(echo "$grouped_files"))

  if [[ -n "$missing" ]]; then
    echo "Warning: these files were not assigned to any group:"
    echo "$missing" | sed 's/^/  /'
    echo ""
  fi

  echo "$clean_json" | jq '.' > "$groups_file"

  echo "Plan saved to $groups_file"
  echo ""
  aigroupcommit --show
  echo "Review/edit: $groups_file"
  echo "Commit: aigroupcommit --commit"
}

# Use 1Password SSH agent
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# vifm: cd into the dir vifm was last in (mc-style "exit drops you here").
# Aliased as `r` to mirror the common mc workflow: r → browse → q → land.
vicd() {
  local dst
  dst="$(mktemp -t vifm-cd.XXXXXX)" || return 1
  vifm --choose-dir="$dst" "$@"
  local target
  target="$(cat "$dst")"
  rm -f "$dst"
  if [ -z "$target" ]; then
    echo 'vicd: no directory chosen'
    return 1
  fi
  cd "$target" || return 1
}
alias r='vicd .'

