# PoC: `govfuzz auto` runs the compiler named in a scanned tree's `compile_commands.json`

Affected: govfuzz 0.2.31 (tested at `v0.2.31-15-g0e646fd`).
Impact: arbitrary command execution on the host running govfuzz, from an untrusted
scanned tree, in default mode, with none of the build-executing flags set.

## Why this is in scope

Two of the in-scope examples in `SECURITY.md` cover this directly:

- "untrusted input to the govfuzz process (a scanned tree, a corpus file, a manifest,
  a `compile_commands.json`) causing memory corruption or code execution in govfuzz itself";
- "govfuzz executing code from a scanned tree without the operator's explicit consent
  ... a path that runs tree-provided code without one of those flags would be a vulnerability."

This is not the out-of-scope "behavior of third-party toolchains govfuzz drives as
subprocesses" case. govfuzz is not running a trusted toolchain that then misbehaves.
It runs an attacker-supplied executable because it accepted the tree's
`compile_commands.json` as the source of the compiler path. The trust decision is
govfuzz's own.

## What the PoC contains

| File | Role |
|------|------|
| `parser.h` | A header-only fuzzable function. Its presence makes `parser.h` a target, which drives the standalone-header preflight. |
| `use_parser.c` | An owning translation unit, so the compile database has a row whose flags apply to `parser.h`. |
| `evilclang` | The attacker's "compiler". Its filename contains `clang`, so it passes the accept check. It writes `PWNED.txt`, then execs the real `clang` so the build still succeeds. |
| `run_poc.sh` | Generates `compile_commands.json` and runs govfuzz in default mode. |

## Run it

```sh
./run_poc.sh /path/to/govfuzz        # or just ./run_poc.sh if govfuzz is on PATH
```

Requirements: `clang` and `make` on PATH (the normal C-lane toolchain).

The script runs, from an unrelated working directory, this and nothing else:

```sh
govfuzz auto <this-folder> --work-dir <this-folder>/gfwork \
  --per-target-time 2 --max-targets 5 --languages c
```

No `--build-command`, `--probe-build`, `--run-untrusted`, or
`--unsafe-search-and-run-build-commands`.

## Expected result

```
>>> CODE EXECUTION CONFIRMED. Contents of PWNED.txt:
govfuzz executed this attacker binary as the compiler from compile_commands.json
when: 2026-09-05T15:12:11Z
who:  uid=1000(dan) gid=1005(dan) ...
argv: <folder>/evilclang -I <folder> -fsyntax-only -x c -
```

`PWNED.txt` is written by `evilclang`, so govfuzz executed it. The `argv` line is the
standalone-header preflight invocation, where govfuzz spawns the database compiler
directly.

## The two delivery shapes

The `run_poc.sh` above uses an absolute compiler path, which resolves regardless of
the caller's working directory. A relative path works too when govfuzz is run from
inside the tree:

| `arguments[0]` in `compile_commands.json` | How govfuzz is invoked | Runs the attacker binary? |
|---|---|---|
| `<abs>/evilclang` | `govfuzz auto <abs>` from anywhere | yes |
| `./evilclang` | `cd <tree> && govfuzz auto .` | yes |
| `./evilclang` | `govfuzz auto <abs>` from an unrelated dir | no (relative path does not resolve to the tree) |

The absolute shape matters for automation: CI checks out at a fixed path
(`/home/runner/work/<repo>/<repo>` on GitHub Actions, `/github/workspace` in a
container, `/builds/<group>/<project>` on GitLab), so a repository or pull request
fuzzed by govfuzz in a pipeline can pin the path and get execution on the runner.

## Root cause (code pointers, `crates/cli/src/generate_harness.rs`)

- `compile_database_candidates` (line 7766) walks upward from each source file and
  reads a `compile_commands.json` found in any parent directory, including the tree
  root. The database is taken from the scanned tree, not just the one govfuzz
  generates under `.govfuzz-build/`.
- `compile_command_compiler` (line 8814) accepts the entry's first argument as the
  compiler when its lowercased filename contains `clang`, or equals `gcc`/`g++`
  (or a `gcc-`/`g++-` variant). The path is never checked against a real toolchain.
- The accepted string is spawned: `preflight_header_includes` runs
  `std::process::Command::new(&compiler)` (line 9513) for a header target, and the
  per-TU build recipe runs `{compiler} ... -c ...` under `make`.
- `crates/harness_gen/src/build_safety.rs` only rejects shell/make metacharacters.
  A plain path has none, so it passes. That filter stops recipe injection; it does
  not stop an arbitrary program from being trusted as the compiler.

## Suggested fix

- Do not execute a compiler taken from a scanned tree's `compile_commands.json`
  unless the operator opted in the same way the build-recovery flags require.
- If a database compiler is honored, resolve it via PATH only (reject any value
  containing a path separator), or require its name to match a small allowlist of
  real toolchains resolved from the operator's environment rather than the tree.
- Prefer govfuzz's own trusted compiler for the harness build and preflight, and
  take only flags (already allowlisted in `extract_compile_database_flags`) from the
  database, never the compiler executable.

## Notes

- Tested on Linux with govfuzz built at `v0.2.31-15-g0e646fd`, clang 19, make present.
- `evilclang` execs the real `clang` after writing its marker, so the run finishes
  normally and the effect is easy to miss without the marker file.
- `gfwork/`, `PWNED.txt`, and the generated `compile_commands.json` are gitignored so
  the folder ships clean.
