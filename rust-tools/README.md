# Rust CLI tools

Faster, friendlier replacements for everyday terminal tools. The workload on this box is
terminals, an editor and many coding agents, so the shell is where most of the time goes.
None of these change the workflow: the old commands keep working, the new ones sit next to
them.

| Tool | Replaces | Why |
|---|---|---|
| [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) | `grep -r` | Recursive code search, respects `.gitignore`, skips binaries, much faster |
| [fd](https://github.com/sharkdp/fd) | `find` | Simple syntax (`fd pattern`), respects `.gitignore`, coloured output |
| [bat](https://github.com/sharkdp/bat) | `cat` | Syntax highlighting, line numbers, git change markers |
| [zoxide](https://github.com/ajeetdsouza/zoxide) (`z`) | `cd` | Jumps to frequently used directories by part of the name |
| [Starship](https://starship.rs) | bash `PS1` | Fast prompt with git branch, status and language versions |
| [Zellij](https://zellij.dev) | tmux / screen | Terminal multiplexer with layouts, panes and detachable sessions |

More in the curated list: [Awesome Rust: applications](https://github.com/rust-unofficial/awesome-rust#applications).

## Install

```
sudo ./rust-tools/rust-tools.sh            # desktop user defaults to the user who ran sudo
sudo ./rust-tools/rust-tools.sh someuser
sudo NO_PROMPT=1 ./rust-tools/rust-tools.sh  # keep the stock bash prompt
```

What it does:

- `apt-get install ripgrep fd-find bat zoxide` (all in Ubuntu 24.04 universe).
- Symlinks `/usr/local/bin/fd` to `fdfind` and `/usr/local/bin/bat` to `batcat`. Ubuntu renames
  both binaries to avoid name clashes with older packages; the symlinks restore the upstream
  names so docs and muscle memory work.
- Downloads the latest Starship and Zellij musl builds from GitHub releases into
  `/usr/local/bin` (neither is packaged for 24.04). Re-run the script to upgrade them.
- Appends one marked block to `~/.bashrc` (backup in `~/.bashrc.pre-rust-tools`) that loads
  zoxide and the Starship prompt. Runs once; a second run leaves the block alone.

Never restarts xrdp. Open a new terminal (or `source ~/.bashrc`) afterwards.

### Manual install, one tool at a time

```
sudo apt install ripgrep fd-find bat zoxide
sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
sudo ln -sf /usr/bin/batcat /usr/local/bin/bat

# Starship (official installer, or the release tarball as the script does)
curl -sS https://starship.rs/install.sh | sh

# Zellij
curl -fsSL https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz \
  | sudo tar -xz -C /usr/local/bin zellij

# ~/.bashrc
eval "$(zoxide init bash)"
eval "$(starship init bash)"
```

With a Rust toolchain, `cargo install ripgrep fd-find bat zoxide starship zellij --locked`
works too, but it compiles everything from source, which takes a long time on a small VPS.
[cargo-binstall](https://github.com/cargo-bins/cargo-binstall) fetches prebuilt binaries
instead.

## Quick use

```
rg 'TODO' src/                 # search contents; -i ignore case, -t py only Python, -uu include ignored
fd '\.sh$'                     # find files by regex; -e sh by extension, -H include hidden
bat xrdp.ini                   # highlighted view; -p plain, -A show whitespace
z tune                         # jump to the most used directory matching "tune"; zi to pick
zellij                         # new session; zellij attach -c work to reattach or create
```

Zellij pairs well with RDP: start agents inside a named session (`zellij attach -c agents`),
and they keep running when the tablet disconnects or Konsole closes. Reattach from any
terminal, including a plain SSH login.

Latency notes for a GPU-less RDP desktop:

- Starship redraws only the prompt line, so it costs nothing extra to encode. Use a preset
  without Nerd Font icons unless the font is installed: `starship preset plain-text-symbols -o ~/.config/starship.toml`.
- Zellij's status bars and pane frames repaint on every change. `zellij options --simplified-ui true --pane-frames false`
  (or the same keys in `~/.config/zellij/config.kdl`) keeps the redraws small.

## Benchmark

`bench.sh` times each GNU tool against its Rust counterpart on a directory tree:

```
./rust-tools/bench.sh <dir> [runs] [pattern] [extension]   # defaults: 5 runs, TODO, ts
```

It warms the cache with one run, then reports the median wall time and the output line
count. The line count shows how much each tool actually searched: `rg` and `fd` skip
`.gitignore`'d, hidden and binary files by default, while `-uuu` (rg) and `-uu` (fd) make
them cover the same files as `grep` and `find`.

Measured on the target VPS (6 vCPU, 11 GB RAM, no GPU), `LANG=C.UTF-8`, October 2026:

- **eng2**: one Vite/React repo, 764 MB, 62,579 files, mostly `node_modules`. Fits in the
  page cache; 5 runs.
- **all projects**: 22 project folders, 14 GB, 605,019 files. Larger than free RAM, so content searches
  read from disk on every pass; 1 run.

| Task | Command | eng2 | lines | all projects | lines |
|---|---|---:|---:|---:|---:|
| Literal search `TODO` | `grep -rn` | 1546 ms | 3,192 | 180.9 s | 30,083 |
| | `grep -rn --exclude-dir=node_modules,.git` | 42 ms | 0 | 80.4 s | 4,878 |
| | `rg -n` | 31 ms | 0 | 0.45 s | 280 |
| | `rg -n -uuu` | 401 ms | 3,192 | 60.8 s | 30,290 |
| Regex `error\|warn`, ignore case | `grep -rniE` | 1404 ms | 162,972 | 169.9 s | 1,972,843 |
| | `rg -ni` | 37 ms | 1,793 | 0.23 s | 39,284 |
| | `rg -ni -uuu` | 678 ms | 162,985 | 61.0 s | 1,983,606 |
| Find `*.ts` | `find -name` | 271 ms | 16,718 | 2.83 s | 115,742 |
| | `find` with `-prune` of `node_modules`, `.git` | 24 ms | 319 | 0.63 s | 1,539 |
| | `fd -e ts` | 45 ms | 319 | 0.06 s | 1,496 |
| | `fd -uu -e ts` | 181 ms | 16,718 | 0.74 s | 115,742 |
| List every file | `find -type f` | 300 ms | 62,579 | 2.37 s | 605,019 |
| | `fd -uu -t f` | 200 ms | 62,579 | 1.01 s | 605,019 |
| Print a 1-2 MB JSON file | `cat` | 17 ms | | 12 ms | |
| | `bat -pp` | 45 ms | | 116 ms | |
| | `bat --color=always` | 1843 ms | | 1534 ms | |

What it shows:

- Searching the same files, `rg` is 2 to 4 times faster than `grep` (60 s against 170 to
  180 s on the full tree), and `fd` is 1.5 to 4 times faster than `find`.
- The bigger win is what they skip. On the full tree, `rg TODO` takes 0.45 s against 181 s
  for `grep -rn`, and its 280 matches are the ones in project code; the other 30,000 are in
  `node_modules`, build output and vendored files.
- Excluding `node_modules` and `.git` by hand is enough for `grep` on a single repo, but not
  across many: the full tree still took 80 s because each repo ignores other things too
  (`dist`, `.venv`, `target`, archives). `rg` reads each repo's own `.gitignore`.
- `bat` is for people, not pipes: highlighting costs about 100 times more than `cat`.
- zoxide, Starship and Zellij have no direct counterpart to time and are not benchmarked.

## Tell coding agents to use them

Agents read a global instruction file at session start. Put the rules in one shared file and
point each agent at it, the same way `RTK.md` is shared in this setup.

### 1. Shared rules file

Save as `~/.claude-shared/TOOLS.md`:

```markdown
# Shell tools

Prefer these tools when they are installed (check once with `command -v`). Fall back to the
standard tool when they are not, and never install them unasked.

- Search file contents with `rg` instead of `grep -r`. It respects `.gitignore` and skips
  binary files; add `-uu` to search ignored and hidden files too.
- Find files by name with `fd` instead of `find`. On Debian/Ubuntu the binary may be
  `fdfind`. Add `-H` for hidden files and `-I` for ignored files.
- Read files with `cat`, `sed -n` or your file-read tool, not `bat`: its decorations waste
  tokens. Use `bat` only when showing a file to a person.
- Do not use `z`/zoxide in commands or scripts. Its jumps depend on the user's history and
  are not reproducible. Use explicit paths with `cd`.
- Do not start, attach to or kill Zellij sessions unless asked. A long-running process may
  belong to the user's session.
```

### 2. Point each agent at it

| Agent | Global file | How |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `ln -s ~/.claude-shared/TOOLS.md ~/.claude/TOOLS.md`, then add the line `@TOOLS.md` |
| Codex CLI | `~/.codex/AGENTS.md` | Paste the rules into the file. Codex does not document `@` imports, so an `@` line may reach the model as plain text |
| opencode | `~/.config/opencode/AGENTS.md` | Paste the rules into the file, or list the shared file under `"instructions"` in `~/.config/opencode/opencode.json` |
| Gemini CLI | `~/.gemini/GEMINI.md` | Add `@/home/<user>/.claude-shared/TOOLS.md` (Gemini CLI expands `@file` imports) |
| Others | `AGENTS.md` in the repo root | Most other agents read this per project; paste the rules there |

Claude Code, as a one-off:

```
ln -sf ~/.claude-shared/TOOLS.md ~/.claude/TOOLS.md
grep -qxF '@TOOLS.md' ~/.claude/CLAUDE.md || printf '\n@TOOLS.md\n' >> ~/.claude/CLAUDE.md
```

Check it loaded: start a new session and ask "which tool do you use to search file contents?".

Notes:

- Claude Code's built-in Grep and Glob tools already use ripgrep internally, so the rules
  matter mostly for commands it runs through Bash and for other agents.
- Keep the file short. Every line loads into every session and costs tokens each turn.
- "When installed" matters: the same instruction file follows you to machines that do not
  have the tools, and the agent must not fail or start installing packages there.

## Rollback

Remove the `# >>> rust-tools >>>` block from `~/.bashrc` (or restore
`~/.bashrc.pre-rust-tools`), then:

```
sudo rm /usr/local/bin/{fd,bat,starship,zellij}
sudo apt-get remove ripgrep fd-find bat zoxide
```
