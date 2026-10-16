# Grok CLI and Vikunja

The Grok CLI marks Vikunja tasks off through `vk-list` and `vk-done`
from `bashrc.d/vikunja.bashrc`. It doesn't get the full API.

Credentials live in `~/.config/vikunja/grok-cli.env`, outside this repo,
with `chmod 600`:

```text
VIKUNJA_URL=https://tasks.stealthdragonland.net/api/v1
VIKUNJA_TOKEN=<token for the bot-grok-cli Vikunja account>
```

Grok loads `~/.grok/AGENTS.md` before every session. machine-setup
ships that file as `setup/files/home/grok-AGENTS.md`, and
`link-home-files.sh` links it in. The task rules live there.
