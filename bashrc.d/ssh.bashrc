#!/usr/bin/env bash

# Git/ssh from VS Code (and other GUI tools) try ssh-askpass over X11
# when DISPLAY is set. That fails on Hyprland. Force the tty/agent path.
export SSH_ASKPASS_REQUIRE=never
unset SSH_ASKPASS

case "$HOSTNAME" in

    *media*|*node*)
        [[ -t 1 ]] && echo 'Skipping SSH Setup'
        ;;

    *Dragon*)
        function ssh-dragonfire {
            ssh root@192.168.0.1
        }
        function ssh-dragondev {
            ssh dragon@192.168.0.14
        }
        function ssh-amd-node {
            ssh dragon@amd64node"$1".lan
        }
        ;;
    *)
        SSH_ENV="$HOME/.ssh/environment"

        function run_ssh_env {
            # shellcheck disable=SC1090
            [ -f "${SSH_ENV}" ] && . "${SSH_ENV}" > /dev/null
        }

        function add_ssh_keys {
            for key in "$HOME"/.ssh/id_*; do
                if [[ -f "$key" && ! "$key" =~ \.pub$ && ! "$key" =~ (config|known_hosts|environment|authorized_keys)$ ]]; then
                    ssh-add "$key"
                fi
            done
        }

        function start_ssh_agent {
            echo "Initializing new SSH agent..."
            ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
            chmod 600 "${SSH_ENV}"
            run_ssh_env
            add_ssh_keys
        }

        run_ssh_env
        ssh-add -l > /dev/null 2>&1
        case $? in
            0) ;;                 # agent alive, keys loaded
            1) add_ssh_keys ;;    # agent alive, no keys
            *) start_ssh_agent ;; # can't reach an agent
        esac
        ;;
esac
