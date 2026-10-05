# To do: bash 3.2 on macOS

## The problem

Every syskit script begins with a bash-version guard:

```bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
```

Scripts use bash 4 features (associative arrays, `mapfile`, `${var,,}` and similar), so they
need bash 4 or newer. macOS ships bash 3.2 and Apple does not update it.

The guard runs before any OS check. On a stock Mac it exits with the install hint, so the
macOS messages added to many scripts (Docker Desktop, "not applicable on macOS", and so on)
are only reachable once Homebrew bash is installed.

## What already works

Homebrew bash is found automatically whenever it is first on `PATH`, because every script uses
`#!/usr/bin/env bash`. On the Mac that is `/opt/homebrew/bin/bash`, which comes before `/bin`.

The one-time setup is `brew install bash`. Nothing else is needed for an interactive shell.

The guard only fires when bash 3.2 is what runs, for example `/bin/bash script.sh`, cron, or a
GUI launch with a minimal `PATH`.

## Decision

**Option 1 chosen (2026-10-05): keep the guard as it is.** It stops with the install hint.
Installing Homebrew bash is a one-time step, and the narrow cases where the guard fires
(explicit `/bin/bash`, cron, GUI launches) are rare. Option 2 is not being pursued.

- **Option 1 (chosen):** keep the guard as it is. Stop with the install hint.
- **Option 2 (not pursued):** when bash 3.2 is running on macOS, hand off to Homebrew bash if it
  is installed. Otherwise print the same hint and stop. It would only save a manual re-run in the
  narrow cases above, and it still needs Homebrew bash installed.
- **Option 3 (rejected):** rewrite scripts to run on bash 3.2.

The rest of this file is kept for reference in case the decision is revisited.

## Proposed guard (option 2)

Replace line 2 of every bash-guarded script with:

```bash
if ((BASH_VERSINFO[0] < 4)); then
    for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [ -x "$b" ] && exec "$b" "$0" "$@"
    done
    echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1
fi
```

Notes:
- Each script carries its own copy. This follows the standalone-scripts rule.
- `return ... || exit` keeps sourced scripts working as they do now.
- The `if` body never runs on Linux, which has bash 4+.

## Scope

- 358 files contain the current guard line.
- Scripted edit of line 2 in each file. Keep the `return ... || exit` behaviour.

## Verification

1. `bash -n` on all 358 files.
2. On this Mac, `/bin/bash <script>` with Homebrew bash installed: the script should hand off and run.
3. On this Mac with Homebrew bash absent: the hint should print and the script should stop.
4. Linux: spot-check on `mina` and `susew`. The guard should be silent.

## Risks

- Low. The change only runs under bash 3.2 on macOS.
- It is a large diff. Commit it on its own so it can be reviewed or reverted.
