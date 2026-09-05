# scripts

Helpers called from `bashrc.d`, not part of the role installer.

| File                                       | Used by                               |
| ------------------------------------------ | ------------------------------------- |
| `ffmpeg.py`                                | `bashrc.d/ffmpeg.bashrc`              |
| `dictation.py`                             | `bashrc.d/ai.bashrc` (`ai-dictate`)   |
| `mc_mod_downloader.py` + `mc_modlist.conf` | `bashrc.d/minecraft.bashrc`           |
| `config/podcast-downloader.json`           | `bashrc.d/podcast.bashrc`             |
| `install-omp.sh`                           | `setup/modules/install-oh-my-posh.sh` |

These expect a working Python user environment from the workstation
`install-python-dev` module (`poetry`, `requests`, and friends).
