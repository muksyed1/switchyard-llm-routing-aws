# Switchyard Notes:

## Binary (not in Git)

`files/switchyard-server` is gitignored (26 MB). Build it once on an
Ubuntu 24.04 x86_64 host and copy it here:

```bash
    sudo apt-get install -y build-essential curl git
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    source "$HOME/.cargo/env"
    cargo install --locked switchyard-server        # ~15+ min on t3.small
    # then copy ~/.cargo/bin/switchyard-server into roles/switchyard/files/
```