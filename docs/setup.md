# OpenCode Setup for LCLS Users

Add the following to your `~/.bashrc`:

```bash
opencode() {
    local bin_dir="/sdf/group/lcls/ds/dm/apps/dev/code/.opencode/bin"
    local config_dir="/sdf/group/lcls/ds/dm/apps/dev/opencode"

    if [[ "$1" == "--local" ]]; then
        shift
        bin_dir="$HOME/.opencode/bin"
        config_dir="$HOME/.config/opencode"
    fi

    OPENCODE_CONFIG_DIR="$config_dir" PATH="$bin_dir:$PATH" command opencode "$@"
}
```

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
