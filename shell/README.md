# shell

Login and interactive bash entrypoints. `bashrc.d/` stays at the repo
root so `DOTFILES_ROOT` can keep being "parent of bashrc.d".

| File                | Linked or sourced as                                      |
| ------------------- | --------------------------------------------------------- |
| `linux.bashrc`      | `~/.bashrc` on Linux (via `link-dotfiles`)                |
| `git-bash.bashrc`   | Git Bash `~/.bashrc` / `~/.bash_profile` on Windows work  |
| `omp.yaml`          | Oh My Posh theme                                          |

There is no shipped `~/.profile`. `linux.bashrc` sources `/etc/profile`,
and `bashrc.d/01_base_settings.bashrc` already puts `~/bin` on `PATH`.
A leftover distro `~/.profile` on the machine can stay; it is not part
of this repo.
