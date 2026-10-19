# Double Claude

**English** · [Italiano](README.it.md)

Two Claude accounts on the same Mac, without mixing them up.

If you use Claude with a work account and a personal one, you soon find out the two overlap: chats end up in the wrong profile, a personal MCP server shows up at work, the Code tab of the personal app reads the work configuration. `double-claude` separates the two profiles on four levels and checks that they stay separated.

| Level | What gets mixed | How it gets separated |
|---|---|---|
| Account | the sign-in goes to the wrong app | sign in from the browser, one at a time |
| Desktop app | one app, one account | a second copy of the app with `--user-data-dir` |
| Claude Code | chats, MCP, settings in `~/.claude` | `CLAUDE_CONFIG_DIR`, also in the app's Code tab |
| Folders | each one reads the other's files | `Read`/`Edit` deny rules and, if you want, dedicated folders |

## Install

In the Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/francescocolombo/double-claude/main/double-claude -o /tmp/double-claude && zsh /tmp/double-claude install
```

The command downloads a single file, [`double-claude`](double-claude), checks it and copies it to `~/.local/bin`. Then:

```sh
double-claude init      # a few questions, saves the configuration
double-claude doctor    # checks what is separated and what isn't, without changing anything
```

To uninstall, delete `~/.local/bin/double-claude` and the `~/.config/double-claude` folder.

Requirements: macOS, zsh (the default shell), Claude Code installed. No other programs needed: the part that reads and writes JSON runs on JavaScript for Automation, which ships with macOS.

**Language:** Double Claude speaks English, and Italian if your Mac is set to Italian. To choose: `--lang en` or `--lang it` on any command, or `DC_LANG=en` in `~/.config/double-claude/config`.

## Commands

| Command | What it does |
|---|---|
| `init` | sets up the two profiles with a few questions (dedicated folders are optional) |
| `doctor` | checks what is already separated and what isn't, without changing anything |
| `plan` | shows what `apply` would do |
| `apply [parts]` | separates everything, or only `shell`, `move`, `mcp`, `deny`, `app` |
| `open NAME` | opens the right profile's app (the launchers use it) |
| `status` | shows the open Claude apps and their profile |
| `backup` / `restore` | saves a copy and goes back to it |

`apply` always makes a backup before changing anything, in `~/.config/double-claude/backups`. On macOS it's an instant APFS copy that only takes space for what changes afterwards; the last 5 are kept.

## Accounts and profiles

- **Account**: the email you sign in to Claude with.
- **Profile**: where Claude keeps chats, settings and MCP servers on this Mac. The first one is `~/.claude` with the Claude app; the second one is `~/.claude-<name>` with its own copy of the app.

Double Claude gives each account its own profile.

## Dedicated folders (optional)

A profile with a dedicated folder works only there: its command starts only inside that folder, its file tools read only from there, and the other profile can't read it. `init` offers four choices:

1. no dedicated folder: both commands work everywhere;
2. the second profile works only in `~/Documents/<name>`, the first one everywhere else;
3. the first profile works only in `~/Documents/<name>`, the second one everywhere else;
4. one folder each: each profile works only in its own.

The path can be changed, and `apply` creates the folders that don't exist.

The read block uses Claude Code's `permissions.blockReadsOutsideWorkingDirectories` (version 2.1.257 or later) and also applies in the app's Code tab: Read, Grep and Glob refuse files outside the profile's folders. Bash commands that read outside ask for permission; with the sandbox they are blocked.

Dedicated folders also tell whose chats are already mixed. Without dedicated folders, `apply move` moves only the chats started in the Code tab of the second app, whose folder sits inside that app's data. You can add folders later by running `init` again: Double Claude remembers what it wrote in the settings and removes what's no longer needed, without touching your own rules.

## Sandbox (optional)

Deny rules apply to Claude Code's file tools and to commands that name a file, like `cat`, `head`, `sed` and redirects. They don't stop a Python or Node script, or `grep -r`. Claude Code's sandbox applies the same rules to every command, at the system level. The cost: network access for commands goes through an allowlist that starts empty, and Claude asks you about each new site. `init` offers it, off by default.

## The second app

- The app copy doesn't update itself: an update would restart it on the wrong account. `apply app` writes a local policy in the `<data>-3p` folder, but only if the folder doesn't exist: if it's already there (for example for an inference gateway), it leaves it alone and `doctor` reports it.
- When you click the launcher, the copy is rebuilt only if it's older than Claude.app. If it's newer, or its version can't be read, it stays. The new copy is built next to the old one and replaces it only when it's complete.
- The launcher waits for the work to finish: since macOS 27, processes started by an app that quits are stopped.
- Each launcher has its own identifier and Claude's icon. `init` asks whether to keep them out of the Dock (open them from Spotlight) or not (they can be pinned to the Dock).
- If the copy is already open without its profile, the launcher asks whether to quit it and reopen it the right way. `doctor` also checks for the copy pinned in the Dock and for the same account in both apps.

## Where you start from

- **One account, adding a second one.** `init` → `apply`. Moving chats is optional.
- **Two accounts, one profile.** `init` → `plan` → `apply`. With a dedicated folder, the second account's chats and history move to its profile; without one, only the chats started in the second app's Code tab move.
- **Two profiles, but something leaks between them.** `init` → `doctor`, then only the parts marked with ✗.

## Use case

A designer uses Claude with the company account for the projects in `~/Documents/work` and with the personal account for everything else. They already have two apps, but:

- the personal app's Code tab saves chats in the work profile;
- a personal MCP server also shows up in work sessions;
- the Terminal history holds the projects of both.

With `init` they pick "work" and "personal" and choose that work works only in `~/Documents/work`. `doctor` shows four ✗. `apply` moves the personal chats and history, moves the MCP server, writes the deny rules and rebuilds the personal app's launcher with `CLAUDE_CONFIG_DIR`. A second `doctor` shows all ✓.

Result:

```
claude          works only inside ~/Documents/work, company account
claude-personal works everywhere else, personal account, config ~/.claude-personal
Claude          work app
Claude Personal second app, with its own data and Code tab
```

## Known pitfalls

- Sign-in goes through the browser: sign out of claude.ai first and keep the other app closed.
- `CLAUDE_CONFIG_DIR` is read only at startup: after a change, quit the app with ⌘Q.
- The two apps share the same identifier: always open them from the launchers, not from the copy pinned in the Dock.
- Deny rules don't stop scripts and `grep -r`: for those you need the sandbox.
- Some things stay shared: the `claude` program, the app's key in the Keychain, the app's logs and caches. For a complete wall you need a second macOS user.

## Tests

```sh
zsh tests/run.sh                  # JSON engine on node, also runs on Linux
DC_TEST_JXA=1 zsh tests/run.sh    # on macOS: engine on osascript, as in real use
```

The tests use a fake home. The macOS tools (`osacompile`, `open`, `ps`, `codesign`, the Dock) are simulated; `plutil` is the real one, so the app scenario runs only on macOS. On your own Mac, the first safe check is `double-claude doctor`, which changes nothing.

## License

MIT
