# bun update -i: Dots scattered across version columns (v1.4.0 regression)

**Affected:** v1.4.0+ &nbsp;|&nbsp; **Last good:** v1.3.14 &nbsp;|&nbsp; **Introduced by:** [PR #30412](https://github.com/oven-sh/bun/pull/30412) (Rust port)

> Note: the stray `r` appended to package names is a **separate** bug tracked in
> [#30693](https://github.com/oven-sh/bun/issues/30693). This repo covers only the dots.

---

## What's wrong

When you run `bun update -i` on v1.4.0, the spaces between version columns are replaced by
four dots (`....`):

**v1.3.14 — correct:**
```
  □ ai      0.0.1   0.0.1   6.0.191
  □ git-cz  1.8.4   1.8.4   4.9.0
  □ taze    0.18.0  0.18.0  19.14.1
```

**v1.4.0 — broken:**
```
  □ ai....0.0.1....0.0.1....6.0.191
  □ git-cz....1.8.4....1.8.4....4.9.0
  □ taze....0.18.0....0.18.0....19.14.1
```

---

## Why this can only be seen in a real terminal

`bun update -i` is an **interactive TUI**. It checks whether stdout is connected to a
real terminal (TTY) before rendering the package selection UI. If it's not — for example,
inside a test runner, a CI job, or a plain script — bun exits immediately without drawing
anything. There is nothing to observe.

This means **no automated test can invoke `bun update -i` and see the rendered output
in the normal way.** The bug is in the visual output itself, so it must be verified by
a human looking at a terminal.

---

## How to reproduce

### Option 1 — by hand (recommended, most reliable)

```bash
# Clone and install
git clone https://github.com/THernandez03/bun-update-interactive-issue
cd bun-update-interactive-issue
bun install

# Run the interactive updater
FORCE_COLOR=1 bun update -i
```

**What to look for:** The package list appears on screen. On v1.4.0 you will see
`....` (four dots) between the package name and the version numbers, and between
every version column. On v1.3.14 there are clean spaces.

Press `q` or `Ctrl-C` to exit without making changes.

---

### Option 2 — via `reproduce.sh` (automated PTY capture)

`reproduce.sh` works around the TTY requirement by using the `script` command, which
allocates a **pseudo-TTY** (a fake terminal). This tricks bun into rendering its UI.
The script captures the raw output bytes, strips the ANSI colour codes, and prints
the plain text so you can inspect it.

```bash
bash reproduce.sh
# or: bun reproduce
```

**What to look for in the output:** Find the lines that list the package names. They
should look like this on v1.3.14:

```
ai      0.0.1   0.0.1   6.0.191
git-cz  1.8.4   1.8.4   4.9.0
taze    0.18.0  0.18.0  19.14.1
```

On v1.4.0 the spaces are corrupted into dots:

```
ai....0.0.1....0.0.1....6.0.191
git-cz....1.8.4....1.8.4....4.9.0
taze....0.18.0....0.18.0....19.14.1
```

> **Caveat:** `reproduce.sh` does not print PASS or FAIL — it just shows you the
> output. The dots corruption happens at the byte level inside bun, so they survive
> the ANSI strip and are visible in the plain text. Visual inspection is required.
> If the lines look clean in the script output but you are on v1.4.0, confirm by
> running Option 1 directly in your terminal.

---

## Root cause (for the developer fixing this)

The bug is in `src/runtime/cli/update_interactive_command.rs`.

Version columns are rendered like this:

```rust
Output::pretty(format_args!("<d>{}  {}  {}<r>", current_fmt, target_fmt, latest_fmt))
```

Each `{}` is filled by `diff_fmt()`, which returns a version string decorated with
ANSI sequences (underline for changed segments, dim for unchanged):

```
diff_fmt("1.8.4", "4.9.0")
  → \x1b[4m4\x1b[0m.\x1b[4m9\x1b[0m.\x1b[4m0\x1b[0m
```

`format_args!` does the substitution at **runtime**, so `pretty_fmt_runtime` receives
and post-processes the combined string:

```
<d>\x1b[2m1.8.4\x1b[0m  \x1b[4m4.9.0\x1b[0m  \x1b[4m4.9.0\x1b[0m<r>
```

The ANSI CSI bytes already inside the string interact with `pretty_fmt_runtime`'s
`<tag>` scanner, corrupting the two-space separators into `.` characters.

**The Zig reference** (`update_interactive_command.zig`) uses the compile-time `pretty!`
macro, which expands `<tag>` patterns *before* `{}` substitution. The ANSI bytes from
`diff_fmt()` are never scanned — column padding is preserved.

**Fix:** replace `Output::pretty(format_args!(...))` with the compile-time `pretty!`
macro at the call sites that render version columns.

---

## Version bisect

| Version           | Result                                                |
| ----------------- | ----------------------------------------------------- |
| `v1.3.14`         | ✅ Spaces between columns — correct                   |
| `v1.4.0-canary.*` | ❌ Dots between columns — broken (Rust port, PR #30412) |
| `v1.4.0`          | ❌ Dots between columns — broken                      |

---

## Related

- [#30693](https://github.com/oven-sh/bun/issues/30693) — stray `r` after package names (separate bug)
- PR [#30694](https://github.com/oven-sh/bun/pull/30694) — fixes the `r` suffix, does not fix dots
- [#30789](https://github.com/oven-sh/bun/issues/30789) — related rendering regression in `bun update --latest`
