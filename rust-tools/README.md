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
