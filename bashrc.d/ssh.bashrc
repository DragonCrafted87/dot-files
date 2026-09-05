#!/usr/bin/env bash

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
        # Start SSH Agent
        #----------------------------

        SSH_ENV="$HOME/.ssh/environment"

        function run_ssh_env {
            # shellcheck disable=SC1090
            . "${SSH_ENV}" > /dev/null
        }

        function start_ssh_agent {
            echo "Initializing new SSH agent..."
            ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
            echo "succeeded"
            chmod 600 "${SSH_ENV}"

            run_ssh_env;

            # Add only private key files, excluding .pub and known non-key files
            for key in "$HOME"/.ssh/id_*; do
                # Skip if file is a .pub, directory, or known non-key file
                if [[ -f "$key" && ! "$key" =~ \.pub$ && ! "$key" =~ (config|known_hosts|environment|authorized_keys)$ ]]; then
                    ssh-add "$key"
                fi
            done
        }

        if [ -f "${SSH_ENV}" ]; then
            run_ssh_env;
            # shellcheck disable=SC2009
            ps -ef | grep "${SSH_AGENT_PID}" | grep ssh-agent$ > /dev/null || {
                start_ssh_agent;
            }
        else
            start_ssh_agent;
        fi
        ;;
esac
