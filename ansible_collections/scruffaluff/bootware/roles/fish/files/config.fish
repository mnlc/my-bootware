# Fish settings file.
#
# To profile Fish configuration startup time, run command
# 'fish --command exit --profile-startup profile.log'. For more information
# about the Fish configuration file, visit
# https://fishshell.com/docs/current/index.html#configuration-files.

# Do not use flag '--query' instead of '-q'. Flag '--quiet' was renamed to
# '--query' in Fish version 3.2.0, but short flag '-q' is compatible across all
# versions.

# Convenience variables.
#
# Do not use long form flags for uname. They are not supported on MacOS. Command
# "(brew --prefix)" will give the incorrect path when sourced on Apple silicon
# and running under an Rosetta 2 emulated terminal.
#
# Flags:
#   -d: Check if path is a directory.
#   -s: Show operating system kernel name.
if test -d /opt/homebrew
    set _brew_prefix /opt/homebrew
else
    set _brew_prefix /usr/local
end
set _os (uname -s)
if status is-interactive
    set _tty true
else
    set _tty ''
end

# Prompt user to remove current command from Fish history.
#
# Flags:
#   -n: Check if string is nonempty.
function delete_commandline_from_history
    set command (string trim (commandline))
    if test -n "$command"
        set results (history search "$command")

        if test -n "$results"
            printf '\nFish History Entry Delete\n\n'
            history delete "$command"
            history save
            commandline --function kill-whole-line
        end
    end
end

# Open Fish history file with default editor.
#
# Flags:
#   -q: Only check for exit status by supressing output.
function edit-history
    if type -q "$EDITOR"
        $EDITOR "$HOME/.local/share/fish/fish_history"
    end
end

# Prepend existing directories that are not in the system path.
#
# Builtin fish_add_path function changes system path permanently. This
# implementation only changes the system path for the shell session. Do not
# quote the PATH variable. It will convert it from a list to a string.
#
# Flags:
#   -d: Check if path is a directory.
function prepend_paths
    for inode in $argv
        if test -d "$inode"; and not contains "$inode" $PATH
            set --export PATH "$inode" $PATH
        end
    end
end

# Check if current shell is within a remote SSH session.
#
# Flags:
#   -n: Check if string is nonempty.
function ssh_session
    if test -n "$SSH_CLIENT$SSH_CONNECTION$SSH_TTY"
        return 0
    else
        return 1
    end
end

# Source shell files if they exist.
#
# Flags:
#   -f: Check if file exists and is a regular file.
function source_files
    for inode in $argv
        if test -f "$inode"
            source "$inode"
        end
    end
end

# Source Bash files if they exist.
#
# Flags:
#   -f: Check if file exists and is a regular file.
function source_bash_files
    for inode in $argv
        if test -f "$inode"
            bass source "$inode"
        end
    end
end

# Shell settings.

# Disable welcome message.
set fish_greeting

# Set solarized light color theme for several Unix tools.
#
# Uses output of command "vivid generate solarized-light" from
# https://github.com/sharkdp/vivid.
#
# Flags:
#   -f: Check if file exists and is a regular file.
if test -f "$HOME/.ls_colors"
    set --export LS_COLORS (cat "$HOME/.ls_colors")
end

# Add directories to system path that are not always included.
#
# Homebrew ARM directories should appear in system path before AMD directories
# since some ARM systems might have slower emulated AMD copies of programs.
prepend_paths /usr/local/bin /opt/homebrew/bin /opt/homebrew/sbin \
    "$HOME/.local/bin"

# Add custom Fish key bindings. 
#
# To discover Fish character sequences for keybindings, use the
# 'fish_key_reader' command. For more information, visit
# https://fishshell.com/docs/current/cmds/bind.html.
function fish_user_key_bindings
    bind \cD delete_commandline_from_history
end

# Add unified clipboard aliases.
#
# Command cbcopy is defined as a function instead of an alias to add logic for
# removing the final newline from text during clipboard copies.
#
# Flags:
#   -n: Check if string is nonempty.
#   -q: Only check for exit status by supressing output.
#   -z: Read input until null terminated instead of newline.
if test "$_os" = Darwin
    function cbcopy
        set --local text
        while read -z line
            if test -n "$text"
                set
            else
                set text "$line"
            end
        end
        echo -n "$(printf "%s" "$text")" | pbcopy
    end
    alias cbpaste pbpaste
else if type -q wl-copy
    function cbcopy
        set --local text
        while read -z line
            if test -n "$text"
                set
            else
                set text "$line"
            end
        end
        echo -n "$(printf "%s" "$text")" | wl-copy
    end
    alias cbpaste wl-paste
end

# Docker settings.

# Ensure newer Docker features are enabled.
set --export COMPOSE_DOCKER_CLI_BUILD true
set --export DOCKER_BUILDKIT true

# Fzf settings.

# Set Fzf solarized light theme.
set _fzf_colors '--color fg:-1,bg:-1,hl:33,fg+:235,bg+:254,hl+:33'
set _fzf_highlights '--color info:136,prompt:136,pointer:230,marker:230,spinner:136'
set --export FZF_DEFAULT_OPTS "--reverse $_fzf_colors $_fzf_highlights"

# Add inode preview to Fzf file finder.
#
# Flags:
#   -C: Turn on color.
#   -L 1: Descend only 1 directory level deep.
#   -q: Only check for exit status by supressing output.
if type -q bat; and type -q tree
    function fzf_inode_preview
        bat --color always --style numbers $argv 2>/dev/null
        if test $status != 0
            tree -C -L 1 $argv 2>/dev/null
        end
    end

    set --export FZF_CTRL_T_OPTS "--preview 'fzf_inode_preview {}'"
end

# Load Fzf keybindings if available.
#
# Flags:
#   -f: Check if file exists and is a regular file.
#   -n: Check if string is nonempty.
if test -f "$HOME/.config/fish/functions/fzf_key_bindings.fish"; and test -n "$_tty"
    fzf_key_bindings
    # Change Fzf file search keybinding to Ctrl+F.
    bind --erase \ec
    bind --erase \ct
    bind \cf fzf-file-widget
end

# Go settings.

# Export Go root directory to system path if available.
#
# Flags:
#   -d: Check if path is a directory.
if test -d "$_brew_prefix/opt/go/libexec"
    set --export GOROOT "$_brew_prefix/opt/go/libexec"
    prepend_paths "$GOROOT/bin"
else if test -d /usr/local/go
    set --export GOROOT /usr/local/go
    prepend_paths "$GOROOT/bin"
end

# Set path for Go local binaries.
set --export GOPATH "$HOME/.go"
prepend_paths "$GOPATH/bin"

# Helix settings.

# Set full color support for terminal and default editor to Helix.
#
# Flags:
#   -q: Only check for exit status by supressing output.
if type -q hx
    set --export COLORTERM truecolor
    set --export EDITOR hx
end

# Just settings.

# Add alias for account wide Just recipes.
alias jt "just --justfile $HOME/.justfile --working-directory ."

# Kubernetes settings.

# Add Kubectl plugins to system path.
prepend_paths "$HOME/.krew/bin"

# Procs settings.

# Set light theme since Procs automatic theming fails on some systems.
alias procs 'procs --theme light'

# Python settings.

# Fix Poetry package install issue on headless systems.
set --export PYTHON_KEYRING_BACKEND 'keyring.backends.fail.Keyring'
# Make Poetry create virutal environments inside projects.
set --export POETRY_VIRTUALENVS_IN_PROJECT true

# Make numerical compute libraries findable on MacOS.
if test "$_os" = Darwin
    set --export OPENBLAS "$_brew_prefix/opt/openblas"
    prepend_paths "$OPENBLAS"
end

# Add Pyenv binaries to system path.
set --export PYENV_ROOT "$HOME/.pyenv"
prepend_paths "$PYENV_ROOT/bin" "$PYENV_ROOT/shims"

# Initialize Pyenv if available.
#
# Flags:
#   -n: Check if string is nonempty.
#   -q: Only check for exit status by supressing output.
if type -q pyenv; and test -n "$_tty"
    pyenv init - | source
end

# Rust settings.

# Add Rust binaries to system path.
prepend_paths "$HOME/.cargo/bin"

# Starship settings.

# Disable Starship warnings about command timeouts.
set --export STARSHIP_LOG error

# Initialize Starship if available.
#
# Flags:
#   -q: Only check for exit status by supressing output.
if type -q starship
    starship init fish | source
end

# TypeScript settings.

# Add Deno binaries to system path.
set --export DENO_INSTALL "$HOME/.deno"
prepend_paths "$DENO_INSTALL/bin"

# Add NPM global binaries to system path.
prepend_paths "$HOME/.npm-global/bin"

# Initialize NVM default version of Node if available.
#
# Flags:
#   -q: Only check for exit status by supressing output.
if type -q nvm
    nvm use default
end

# Visual Studio Code settings.

# Add Visual Studio Code binaries to system path for Linux.
prepend_paths /usr/share/code/bin

# Wasmtime settings.

# Add Wasmtime binaries to system path.
set --export WASMTIME_HOME "$HOME/.wasmtime"
prepend_paths "$WASMTIME_HOME/bin"

# Zellij settings.

# Autostart Zellij or connect to existing session if within Alacritty terminal.
#
# For more information, visit https://zellij.dev/documentation/integration.html.
#
# Flags:
#   -n: Check if string is nonempty.
#   -q: Only check for exit status by supressing output.
if type -q zellij; and not ssh_session; and test "$TERM" = alacritty
    # Attach to a default session if it exists.
    set --export ZELLIJ_AUTO_ATTACH true
    # Exit the shell when Zellij exits.
    set --export ZELLIJ_AUTO_EXIT true

    # If within an interactive shell for the login user, create or connect to
    # Zellij session.
    #
    # Do not use logname command, it sometimes incorrectly returns "root" on
    # MacOS. For for information, visit
    # https://github.com/vercel/hyper/issues/3762.
    if test -n "$_tty"; and test "$LOGNAME" = "$USER"
        eval (zellij setup --generate-auto-start fish | string collect)
    end
end

# User settings.

# Load user aliases, secrets, and variables.
#
# Flags:
#   -q: Only check for exit status by supressing output.
if type -q bass
    source_bash_files "$HOME/.env" "$HOME/.secrets"
end
source_files "$HOME/.env.fish" "$HOME/.secrets.fish"
