# Cool Codex

Cool Codex is a small macOS CLI for cooling down Codex-heavy sessions without killing your normal Chrome tabs.

It inspects full process commands before taking action, so it can tell the difference between:

- Codex, agent-browser, Playwright, and Chrome for Testing automation browsers
- Regular Google Chrome windows, tabs, and extensions
- Chrome-related processes whose origin is unclear

The safety rule is simple: Cool Codex never kills a Chrome process from its short name alone.

## Install

From GitHub:

```bash
npm install -g github:Nicenonecb/cool-codex
```

From a local checkout:

```bash
npm install -g .
cool-codex --help
```

## Quick Cooldown

Run the default safe cooldown:

```bash
coolcodex
```

That is the same as:

```bash
cool-codex cooldown-safe
```

It will:

- print a heat-source diagnostic
- clean only Codex, agent-browser, or automation Chrome processes
- restart lightweight macOS UI agents: Dock, SystemUIServer, and ControlCenter
- print the diagnostic again

It will not kill normal Google Chrome tabs, and it will not kill WindowServer.

## Commands

```bash
cool-codex list
cool-codex renderers
cool-codex inspect <pid> [pid...]
cool-codex kill-agent-renderers
cool-codex kill-agent
cool-codex kill-pids <pid> [pid...]
cool-codex cooldown
cool-codex cooldown-safe
cool-codex cooldown-ui
cool-codex cooldown-reduce-effects
cool-codex cooldown-restore-effects
cool-codex cooldown-watch
```

`chrome-process-guard` is kept as a legacy command alias for older local installs.

## Safety Model

Cool Codex classifies each process from the complete command line.

Automation markers include:

```text
agent-browser-chrome
~/.agent-browser/browsers/
Google Chrome for Testing + /T/ temporary user-data-dir
Google Chrome for Testing + --remote-debugging-port
```

Normal Chrome markers include:

```text
/Applications/Google Chrome.app/
```

When a Chrome-related process cannot be classified, it is shown as `UNKNOWN_CHROME_RELATED` and skipped by cleanup commands.

## Development

```bash
npm test
```

The test currently verifies Bash syntax for the CLI script.
