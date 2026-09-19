# Git vs Jujutsu (jj) — Should You Switch?

Syskit's `g` script exists because git's raw UX is genuinely hostile to a solo developer syncing personal scripts across several machines — the staging area, diverged-branch messages, and "would be overwritten by merge" errors read like disasters when they're almost always harmless. **Jujutsu (`jj`)** is a newer version control tool that removes most of that friction while using your *existing git repository* as its actual storage — no new hosting, no new remote, nothing GitHub-side changes.

This doc covers what it actually changes, the real caveats, and whether it's a "straight replace" across your Windows, macOS, and Linux machines.

### Summary A: Try It (low-risk, one machine, fully reversible)
*   Install `jj` on **one** machine only (e.g. `hp2`) — see Step 2 below.
*   Run `jj git init --colocate` inside `~/syskit`. This does **not** touch or convert `.git` — it just adds a `.jj/` folder that reads/writes the same git objects.
*   Use `jj` commands for your own edits on that machine for a week or two.
*   Your other machines keep using `g`/plain `git` completely unaffected — they can't tell the difference.
*   Don't like it? Delete `.jj/` and you're back to plain git, zero data loss, because `.git` was never the "secondary" copy — it's the same source of truth the whole time.

### Summary B: The pain points it actually fixes
| Git pain point (things we hit this session) | What `jj` does instead |
|---|---|
| Staging area confusion (`git add` vs forgot to add) | No staging area — every edit is automatically part of an in-progress commit |
| "Would be overwritten by merge" | Doesn't happen — conflicts are stored *inside* commits, never block you |
| Five different undo tools (`reset`, `reflog`, `stash`, `revert`) | One command: `jj undo`, works for literally any operation |
| Diverged-branch panic (`g unstuck`'s whole reason to exist) | Same underlying situation still occurs (two machines, two versions) — but resolving it is a normal `jj rebase`, not a scary error wall |
| Detached HEAD, "must stash before you can do X" | These states mostly don't exist in `jj`'s model |

---

## 1. What `jj` Actually Is

`jj` is not a new hosting service or a fork of git's data format — it's a different **client** that can use a real git repository as its backend ("colocated" mode). Your `.git` directory, your commit objects, your GitHub remote — all identical, all still readable by plain `git` at any time. `jj` just gives you a different, simpler set of commands for interacting with that same data.

Because of this, `jj push`/`jj git push` talks to `github.com/roysubs/syskit` exactly like `g ps` does now. Nothing about the remote, other collaborators (in your case, other machines), or GitHub's view of the repo changes.

---

## 2. Pros, For Your Specific Workflow

*   **No staging area.** You'll never again wonder "did I `git add` that file" — every change in the working directory is automatically part of the commit you're building.
*   **One real undo.** `jj undo` reverses the last operation, whatever it was — no more remembering which of `reset --soft`, `reset --hard`, `git stash`, or `reflog` applies to your situation.
*   **Conflicts don't halt you.** A conflict becomes a normal (if messy) state recorded in a commit, not a blocking error. You can keep working and resolve it whenever convenient, instead of git demanding you fix it *right now* before doing anything else.
*   **Editing old commits auto-propagates.** Fix something two commits back, and everything built on top of it rebases automatically — no manual `rebase --onto` surgery like we did for your header-guard sweep.
*   **Same remote, same GitHub, same history format underneath.** This is genuinely low-risk to trial because of that.

---

## 3. Cons and Caveats (read before committing to it everywhere)

*   **It's newer and moves fast.** Exact command flags for `push`/`fetch`/`rebase` have shifted across releases. Always check `jj help <command>` on whatever version you actually install rather than trusting older tutorials (including this one) verbatim.
*   **Git hooks may not fire.** If you ever add pre-commit/pre-push hooks to this repo, `jj` operations don't necessarily trigger them the way native `git` commands do (since `jj` doesn't go through git's porcelain layer). Not relevant to you today — `g` doesn't use hooks — but worth knowing before you add any.
*   **Submodules and Git LFS support are less mature** than plain git's. Not relevant to `syskit` (a flat repo, no large binaries), but a real gap if you ever start a project that needs either.
*   **GUI tools don't understand `jj`'s model.** If you ever open this repo in VS Code's source control panel or a git GUI, it'll show you plain git commits fine, but has no concept of `jj`'s "working copy is always a commit" idea or its bookmarks — mixing the two can look confusing even though nothing is actually broken.
*   **It's a genuinely different mental model, not just new commands.** The "no staging area, conflicts don't block you" design is a real shift in how you think about commits — give it more than one session before judging it.

---

## 4. Platform-by-Platform: Is It a Straight Replace?

**Short answer: it's an optional layer you add per-machine, not a swap that happens once.** Each machine needs its own `jj` install and its own `jj git init --colocate` inside its own clone — `.jj/` is local metadata, never pushed to the remote, so installing it on `hp2` does nothing to `dell1` or `White`.

**Linux (`hp2`, `dell1`, `White` WSL)** — the most mature, most-used platform for `jj`. Install via `cargo install --locked jj-cli` or Homebrew if you have it (`0-a-helpers/brew-a` already assumes you might). No known major caveats.

**macOS** — equally straightforward via `brew install jj`. The project is actively used cross-platform by its own maintainers; no significant gaps reported.

**Windows** — `jj` ships native Windows binaries (no WSL required to run it), but it's the platform with the least real-world mileage of the three, and it's worth being extra careful here given what we already hit this session:
*   **Line endings.** You've already had CRLF-vs-LF issues purely from a *Windows git client* viewing this Linux-hosted repo over SMB — adding a second tool with its own opinions about line endings into that mix is worth testing carefully (e.g. commit a test file from the Windows `jj` install and diff it against what Linux `git` sees) before trusting it for real work.
*   **The SMB/exec-bit artifact.** We found that viewing this repo through a Windows SMB mount makes `git` misreport every file's executable bit, even with zero real changes. That's a property of the *mount*, not `git` — so it would very likely affect `jj` identically if you ever ran it against the repo over the same kind of network share rather than a native Linux/WSL filesystem.
*   Net advice: if you try `jj` on `White` (WSL) specifically, you're on a real Linux filesystem inside WSL, not an SMB mount, so this is much less of a concern there than it would be running `jj` from native Windows against a network share.

---

## 5. Recommendation

Don't convert everything at once. Install `jj` on `hp2` only, run it in colocated mode, and use it for your own day-to-day edits for a couple of weeks. `g`, `dell1`, `White`, and GitHub itself won't notice or care either way — and if it's not for you, deleting `.jj/` costs you nothing.

## 6. Steps To Try It

```bash
# 1. Install (pick one)
brew install jj                                   # if Homebrew is set up
# — or —
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
cargo install --locked jj-cli

# 2. Turn it on for the existing repo, without touching .git
cd ~/syskit
jj git init --colocate

# 3. Basic loop
#    - edit files, nothing to "add"
jj commit -m "your message"                        # finalize current changes
jj git push                                         # push to the same GitHub remote
jj git fetch                                        # bring down new remote commits
jj rebase -d main@origin                            # bring your work on top of them (check `jj help rebase` for current exact form)

# Undo anything, always:
jj undo
```
