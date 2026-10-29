# OpenCode Setup for LCLS Users

Add the following to your `~/.bashrc`:

```bash
opencode() {
    local bin_dir="/sdf/group/lcls/ds/dm/apps/dev/opencode-cli/current/bin"
    local config_dir="/sdf/group/lcls/ds/dm/apps/dev/opencode"
    local no_update=1   # the team binary is upgraded centrally

    if [[ "$1" == "--local" ]]; then
        shift
        bin_dir="$HOME/.opencode/bin"
        config_dir="$HOME/.config/opencode"
        no_update=          # your own install keeps its update check
    fi

    OPENCODE_DISABLE_AUTOUPDATE="$no_update" OPENCODE_CONFIG_DIR="$config_dir" PATH="$bin_dir:$PATH" command opencode "$@"
}
```

> **Already have this function?** Before 2026-10-29 it pointed `bin_dir` at `/sdf/group/lcls/ds/dm/apps/dev/code/.opencode/bin`, which stays on opencode 1.2.10. Replace the function with the one above to follow the team version, which `tools/opencode/install-opencode.sh` installs and `opencode-sandbox` runs.

Then reload your shell:

```bash
source ~/.bashrc
```

## Usage

```bash
opencode              # uses shared config and agents
opencode --local      # uses your personal ~/.config/opencode instead
```

## What You Get

The shared config includes:
- API key (no personal key needed)
- Pre-configured agents: elog-copilot, daq-logs, confluence-doc, lcls-catalog, smartsheet
