FROM opensuse/leap:15.5

ARG TARGETARCH

# Install Curl and Sudo.  
RUN zypper update --no-confirm && zypper install --no-confirm curl sudo

# Create non-priviledged user and grant user passwordless sudo.
RUN useradd --create-home --no-log-init suse \
    && groupadd sudo \
    && usermod --append --groups sudo suse \
    && printf "suse ALL=(ALL) NOPASSWD:ALL\n" >> /etc/sudoers

ENV HOME=/home/suse USER=suse
USER suse

# Install Bootware.
COPY bootware.sh /usr/local/bin/bootware

# Install dependencies for Bootware.
RUN bootware setup

# Create bootware project directory.
RUN mkdir $HOME/bootware
WORKDIR $HOME/bootware

# Copy bootware project files.
COPY --chown="${USER}" ansible_collections/ ./ansible_collections/
COPY --chown="${USER}" ansible.cfg playbook.yaml ./

ARG skip
ARG tags
ARG test

# VSCode, when run inside of a container, will falsely warn the user about the
# issues of running inside of the WSL and force a yes or no prompt.
ENV DONT_PROMPT_WSL_INSTALL='true'

# Run Bootware bootstrapping.
RUN bootware bootstrap --dev --no-passwd \
    --retries 3 ${skip:+--skip $skip} --tags ${tags:-desktop,extras}

# Copy bootware test files for testing.
COPY --chown="${USER}" tests/ ./tests/

# Ensure Bash and Node are installed.
RUN command -v bash > /dev/null \
    || sudo zypper install --no-confirm --yes bash \
    && command -v node > /dev/null \
    || sudo zypper install --no-confirm nodejs-default

# Set Bash as default shell.
SHELL ["/bin/bash", "-c"]

# Test installed binaries for roles.
#
# Flags:
#   -n: Check if the string has nonzero length.
RUN if [[ -n "${test}" ]]; then \
    source "${HOME}/.bashrc"; \
    node tests/integration/roles.spec.js --arch "${TARGETARCH}" ${skip:+--skip $skip} ${tags:+--tags $tags} "suse"; \
    fi
