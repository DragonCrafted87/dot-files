# scripts

Helpers called from `bashrc.d`, not part of the role installer.

| File                                       | Used by                               |
| ------------------------------------------ | ------------------------------------- |
| `ffmpeg.py` + `ffmpeg_tools/`              | `bashrc.d/ffmpeg.bashrc`              |
| `config/jellyfin.job.example`              | `ffmpeg-jellyfin-init` / plan / apply |
| `dictation.py`                             | `bashrc.d/ai.bashrc` (`ai-dictate`)   |
| `mc_mod_downloader.py` + `mc_modlist.conf` | `bashrc.d/minecraft.bashrc`           |
| `config/podcast-downloader.json`           | `bashrc.d/podcast.bashrc`             |
| `install-omp.sh`                           | `setup/modules/install-oh-my-posh.sh` |

`ffmpeg.py` is the CLI. Implementation is under `ffmpeg_tools/`.
`audio_audible.py` is unfinished on purpose. The bash functions are
wrappers; `ffmpeg.py --help` and the comments above each function in
`bashrc.d/ffmpeg.bashrc` have examples.

Jellyfin sorting uses a `jellyfin.job` text file next to the rip. Init
lists sources; you fill titles / ids; plan prints moves; apply moves.
Override the library root with `JELLYFIN_MEDIA_ROOT` (default
`/home/dragon/Network/Storage/Media`).

These expect a working Python user environment from the workstation
`install-python-dev` module (`poetry`, `requests`, and friends).
DVD helpers also need `dvdauthor` and `mkisofs` from
`install-ffmpeg-tools`.
