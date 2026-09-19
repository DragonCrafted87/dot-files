# Start work in this repo

Copy everything below the line into a new Grok / agent chat.

---

I have the following repo git@github.com:DragonCrafted87/dot-files.git

Read `AGENTS.md` first, then `config/hypr/README.md` and `setup/README.md` if the task touches Hyprland or roles.

Rules that bite:
- `main` is protected. Work on a feature branch and open a PR.
- Clone is `~/dot-files`. User is `dragon`.
- Anything with a shebang keeps an extension unless it is installed onto PATH as a command name.
- Do not invent a second installer; roles go through `setup/role.sh`.
- Host checks use `hostname -s` (`runewyrm`, `forgewyrm`, …).
- Pre-commit lives in Docker (`pre-commit run`). `.scratch/` is excluded.

Task:
