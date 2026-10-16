# Grok CLI and Vikunja

The Grok CLI marks Vikunja tasks off through `vk-list` and `vk-done`
from `bashrc.d/vikunja.bashrc`. It doesn't get the full API.

Credentials live in `~/.config/vikunja/grok-cli.env`, outside this repo,
with `chmod 600`:

```text
VIKUNJA_URL=https://tasks.stealthdragonland.net/api/v1
VIKUNJA_TOKEN=<token for the bot-grok-cli Vikunja account>
```

Grok loads `~/.grok/AGENTS.md` before every session. The linker doesn't
publish `~/.grok`, so add this block to that file by hand:

```markdown
## Vikunja tasks

Scott's to-do board is Vikunja at tasks.stealthdragonland.net.

- Find tasks with `python -I ~/dot-files/scripts/vikunja.py list [search] [-p "Project"]`.
- When work you finished completes a task, mark it with
  `python -I ~/dot-files/scripts/vikunja.py done <id>`.
- Only mark tasks you finished in this session. Do not create, edit,
  or delete tasks unless Scott asks.
- Never print or copy the token from `~/.config/vikunja/grok-cli.env`.
```

The block calls the script directly because Grok's shell may not
source `bashrc.d`.
