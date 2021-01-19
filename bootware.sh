#!/bin/bash
# shellcheck shell=bash
# Exit immediately if a command exists with a non-zero status.
set -e


# Show CLI help information.
#
# Cannot use function name help, since help is a pre-existing command.
usage() {
    case "$1" in
        config)
            cat 1>&2 <<EOF
Bootware config
Generate default Bootware configuration file

USAGE:
    bootware config [OPTIONS]

OPTIONS:
    -h, --help       Print help information
EOF
            ;;
        bootstrap)
            cat 1>&2 <<EOF
Bootware bootstrap
Boostrap install computer software

USAGE:
    bootware bootstrap [OPTIONS]

OPTIONS:
    -c, --config <PATH>             Path to bootware user configuation file
    -h, --help                      Print help information
        --no-passwd                 Do not ask for user password
        --no-setup                  Skip Ansible installation
        ---skip-tags <TAG-LIST>     Ansible playbook tag list
        --tags <TAG-LIST>           Ansible playbook tag list
EOF
            ;;
        main)
            cat 1>&2 <<EOF
$(version)
Boostrapping software installer

USAGE:
    bootware [OPTIONS] [SUBCOMMAND]

OPTIONS:
    -h, --help       Print help information
    -v, --version    Print version information

SUBCOMMANDS:
    config           Generate default Bootware configuration file
    bootstrap        Boostrap install computer software
    update           Update Bootware to latest version
EOF
            ;;
        update)
            cat 1>&2 <<EOF
Bootware update
Update Bootware to latest version

USAGE:
    bootware update [OPTIONS]

OPTIONS:
    -h, --help                  Print help information
    -v, --version <VERSION>     Version override for update
EOF
            ;;
    esac
}

# Assert that command can be found on machine.
assert_cmd() {
    if ! check_cmd "$1" ; then
        error "Cannot find $1 command on computer."
    fi
}

# Bootstrap subcommand.
bootstrap() {
    # Dev null is never a normal file.
    local _config_path="/dev/null"
    local _no_setup
    local _use_passwd="1"
    local _skip_tags
    local _tags

    # Parse command line arguments.
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                usage "bootstrap"
                exit 0
                ;;
            -c|--config)
                _config_path="$2"
                shift
                shift
                ;;
            --no-passwd)
                _use_passwd=""
                shift
                ;;
            --no-setup)
                _no_setup="1"
                shift
                ;;
            --skip-tags)
                _skip_tags="$2"
                shift
                shift
                ;;
            --tags)
                _tags="$2"
                shift
                shift
                ;;
            *)
                ;;
        esac
    done

    if [[ ! "$_no_setup" ]]; then
        setup
    fi

    find_config_path "$_config_path"
    _config_path="$RET_VAL"

    echo "Executing Ansible pull..."
    echo "Enter your user account password if prompted."

    ansible-pull \
        ${_use_passwd:+ --ask-become-pass} \
        --extra-vars "ansible_python_interpreter=auto_silent" \
        --extra-vars "user_account=$USER" \
        --extra-vars "@$_config_path" \
        --inventory 127.0.0.1, \
        ${_skip_tags:+ --skip-tags "$_skip_tags"} \
        ${_tags:+ --tags "$_tags"} \
        --url https://github.com/wolfgangwazzlestrauss/bootware.git \
        main.yaml
}

# Check if command can be found on machine.
check_cmd() {
    command -v "$1" > /dev/null 2>&1
}

# Config subcommand.
config() {
    assert_cmd curl

    # Parse command line arguments.
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                usage "config"
                exit 0
                ;;
            *)
                ;;
        esac
    done

    echo "Downloading default configuration file to $HOME/bootware.yaml..."

    # Download default configuration file.
    #
    # FLAGS:
    #     -L: Follow redirect request.
    #     -S: Show errors.
    #     -f: Use archive file. Must be third flag.
    #     -o <path>: Write output to path instead of stdout. 
    curl -LSf \
        "https://raw.githubusercontent.com/wolfgangwazzlestrauss/bootware/master/host_vars/bootware.yaml" \
        -o "$HOME/bootware.yaml"
}

# Print error message and exit with error code.
error() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

# Find path of Bootware configuation file.
find_config_path() {
    if test -f "$1" ; then
        RET_VAL="$1"
    elif test -f "$(pwd)/bootware.yaml" ; then
        RET_VAL="$(pwd)/bootware.yaml"
    elif [[ -n "${BOOTWARE_CONFIG}" ]] ; then
        RET_VAL="$BOOTWARE_CONFIG"
    elif test -f "$HOME/bootware.yaml" ; then
        RET_VAL="$HOME/bootware.yaml"
    else
        error "Unable to find Bootware configuation file."
    fi

    echo "Using $RET_VAL as configuration file."
}

# Configure boostrapping services and utilities.
setup() {
    local _os_type

    # Get operating system for local machine.
    #
    # FLAGS:
    #     -s: Print the kernel name.
    _os_type=$(uname -s)

    case "$_os_type" in
        Darwin)
            setup_macos
            ;;
        Linux)
            setup_linux
            ;;
        *)
            error "Operting system $_os_type is not supported."
            ;;
    esac

    ansible-galaxy collection install community.general > /dev/null
    ansible-galaxy collection install community.windows > /dev/null
}

# Configure boostrapping services and utilities for Linux.
setup_linux() {
    assert_cmd apt-get
    assert_cmd dpkg

    # dpkg -l does not always return the correct exit code. dpkg -s does. See
    # https://github.com/bitrise-io/bitrise/issues/433#issuecomment-256116057
    # for more information.
    if ! dpkg -s ansible &>/dev/null ; then
        echo "Installing Ansible..."
        sudo apt-get -qq update && sudo apt-get -qq install -y ansible
    fi
}

# Configure boostrapping services and utilities for MacOS.
setup_macos() {
    # Install XCode command line tools if not already installed.
    #
    # Homebrew depends on the XCode command line tools.
    if ! xcode-select -p &>/dev/null ; then
        echo "Installing command line tools for XCode..."
        sudo xcode-select --install
    fi

    # Install Homebrew if not already installed.
    #
    # FLAGS:
    #     -L: Follow redirect request.
    #     -S: Show errors.
    #     -f: Fail silently on server errors.
    #     -s: Disable progress bars.
    if ! check_cmd brew ; then
        echo "Installing Homebrew..."
        curl -LSfs "https://raw.githubusercontent.com/Homebrew/install/master/install.sh" | bash
    fi

    # Install Ansible if not already installed.
    #
    # FLAGS:
    #     ---background:
    if ! brew list ansible &>/dev/null ; then
        echo "Installing Ansible..."
        brew install ansible
    fi
}

# Update subcommand.
update() {
    assert_cmd curl

    local _dest
    local _source
    local _version="master"

    _dest=$(realpath $0)

    # Parse command line arguments.
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                usage "update"
                exit 0
                ;;
            -v|--version)
                shift
                _version="$2"
                ;;
            *)
                ;;
        esac
    done

    _source="https://raw.githubusercontent.com/wolfgangwazzlestrauss/bootware/$_version/bootware.sh"
    if [ -O "$_dest" ]; then
        _sudo=""
    else
        assert_cmd sudo
        _sudo=sudo
    fi

    echo "Updating Bootware..."

    ${_sudo} curl -LSfs "$_source" -o "$_dest"
    ${_sudo} chmod 755 "$_dest"

    echo "Updated to version $(bootware --version)."
}

# Get Bootware version string
version() {
    echo "Bootware 0.0.4"
}

# Script entrypoint.
main() {
    assert_cmd chmod
    assert_cmd git
    assert_cmd mkdir
    assert_cmd mktemp
    assert_cmd uname

    # Parse command line arguments.
    for arg in "$@"; do
        case "$arg" in
            config)
                shift
                config "$@"
                exit 0
                ;;
            bootstrap)
                shift
                bootstrap "$@"
                exit 0
                ;;
            update)
                shift
                update "$@"
                exit 0
                ;;
            -v|--version)
                version
                exit 0
                ;;
            *)
                ;;
        esac
    done

    usage "main"
}

# Execute main with command line arguments.
main "$@"
