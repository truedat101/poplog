# pop11 skill — status & post-demo checklist

Last updated: 2026-08-01 (post-validation, pre-demo). Companion docs: [SKILL.md](SKILL.md)
(usage), [demo/DEMO.md](demo/DEMO.md) (walkthrough),
[../../tools/bench-skill/README.md](../../../tools/bench-skill/README.md)
(numbers).

## ✅ Done (validated end-to-end on macOS arm64, 2026-07-31)

- [x] `popsession` runtime — persistent basepop11 across shell invocations
      (FIFO + inherited O_RDWR fd, no daemon); mishap-proof via `skill_run`
      `dlocal interrupt` trap; per-send unique sentinels; spool-file chunks
- [x] Checkpoint / restore via saved images (raw-send path; state + native
      procedures survive process death; ~190 KB image, ~8 ms restore)
- [x] `pop11run` one-shot runner
- [x] `popcurl` HTTPS shim (runtime dlopen, non-variadic surface; GET/POST;
      curl-CLI fallback) + `build-popcurl`
- [x] SKILL.md crash course; 5-beat demo script; session-retention benchmark
- [x] `install.sh` — one-command setup from a checkout (engine discovery,
      persisted config, `~/.claude/skills` link, shim build, live smoke test)
- [x] `popsqlite` sqlite shim (2026-08-01) — int-handle surface over
      sqlite3 (open/exec/prepare/step/bind, all values as text, NULL→false)
      + generated loader with `sqlite_query`/`sqlite_run_b` conveniences.
      Measured against the field scenario that motivated it: 52-query
      report pass 435 ms via sqlite3-CLI spawns → 6.5 ms in-session;
      ~47 µs/query steady-state (~180×).

## 📚 Library roadmap — what great tooling/shell orchestration needs

Priority order. "P" = pure Pop-11 (portable to every port for free),
"C" = needs a small C shim like popcurl.

None of these block the skill: the 2026-08-01 odysseus field trials went
4/4 with zero of them written, using shipped builtins + CLI bridges
(jq, sqlite3, sysobey). This roadmap deepens the "in-process at
microsecond cost" story; ranked by field evidence, not theory.

- [x] **sqlite shim** — DONE 2026-08-01, see above. v0.2 ideas: typed
      column accessors (int64/double), blob support, `sqlite_rows_iter`
      streaming for huge result sets.
- [ ] **lib shell** (P, 2–3 days) — real process orchestration, the core of
      "tooling/shell" work. `run(cmd) -> (output_string, status)`,
      `run_lines(cmd) -> list`, stderr capture, exit-code access, timeout
      kill, background jobs + wait, pipelines. Built on
      `syspipe`/`sys_fork`/`sys_wait` (today only fire-and-forget `sysobey`
      / `sys_obey_linerep` exist — no clean status or stderr capture; the
      trials worked, but a silent failure of a spawned command would have
      been invisible).
- [ ] **lib json** (P, 2–4 days) — recursive-descent parser + printer;
      objects→properties, arrays→vectors; `\uXXXX`; JSONTestSuite pass.
      Biggest *capability* gap, but no field trial has needed it yet —
      promote when a real API/JSON task shows up.
- [ ] **lib fileutils** (P, 1–2 days) — `file_to_string`, `string_to_file`,
      `file_lines -> list`, glob via `sys_file_match`, directory walk,
      stat/mtime/size, temp files, path join/split.
- [ ] **lib strutils** (P, 1–2 days) — split/join/trim/replace/starts/ends,
      regexp convenience over the Ved regexp engine, `sprintf`-style
      formatting. (Words-vs-strings friction lives here; good helpers cut
      model errors.)
- [ ] **popcurl v0.2** (C, 2–3 days) — request/response headers, body→string
      (write-callback), status + error string accessors, auth, per-call
      timeout, proxy env. Then: retire the "no headers" caveat in SKILL.md.
- [ ] **lib argvenv** (P, 0.5 day) — `poparglist` niceties, `getenv`/
      `setenv` (`systranslate`), script exit codes for `pop11run`.
- [ ] **lib csv** (P, 1 day) — read/write CSV/TSV to lists/vectors; pairs
      with lib json for report pipelines.
- [ ] **lib datetime** (P, 1 day) — epoch/ISO-8601 parse + format over
      `sys_real_time`.

## 🔧 Runtime hardening (popsession)

- [ ] `popsession interrupt` — SIGINT a runaway chunk without killing the
      session (needs a check that batch-mode SIGINT doesn't exit basepop11)
- [ ] Auto-checkpoint on `stop` (`--checkpoint-on-stop PATH`), plus
      `popsession log` (tail out.log) and log rotation
- [ ] Structured send results (`--json`: output, error flag, duration)
- [ ] Long-running-chunk progress: stream output as it appears rather than
      only at sentinel time
- [ ] Multi-session docs + `popsession list`
- [ ] Grow SKILL.md's mishap decoder from real observed model errors
      (each documented error-pattern saves a full model retry turn)

## 📦 Developer experience / distribution — the "one command" ladder

Today (works now, from a checkout):

```sh
sh .claude/skills/pop11/install.sh [--poplog-root DIR]
```

discovers the engine, persists it to `~/.cache/pop11-skill/config.json`
(so no env var is ever needed), links the skill into `~/.claude/skills/`
for all projects, builds popcurl, and smoke-tests a live session.

The ladder to true one-command-from-nothing (in order):

- [x] **Relocatable binary tarballs** — `tools/release-skill-tarball.sh`
      packages a built tree (wrapper + basepop11 + pop/lib + skill/) as
      `pop11-skill-<os>-<arch>.tar.gz` — **2.4 MB** on macos-arm64 (~12 MB
      unpacked: one 4.4 MB engine binary — pop11/clisp/prolog/pml are hard
      links to it, so ship just basepop11 — plus 7.2 MB pop/lib). Relocation
      verified: rewriting the wrapper's `poplogroot=` line is the only
      fix-up needed (binaries/images/autoload are path-clean).
- [x] **`tools/install-skill.sh` network installer** — the true one-liner:
      `curl -fsSL https://raw.githubusercontent.com/IoTone/poplog/master/tools/install-skill.sh | sh`
      downloads the platform tarball from the latest GitHub release, unpacks
      to `~/.local/share/pop11-skill`, relocates, runs the bundled
      install.sh (config, skill link, popcurl, live smoke test).
      `POP11_SKILL_URL`/`POP11_SKILL_PREFIX` override for pinning/testing.
      Full chain validated locally via a `file://` URL in a sandbox $HOME.
- [x] **Publish the assets** — done 2026-07-31: release `v160200-skill`
      carries pop11-skill tarballs for macos-arm64 and linux-x86_64 (plus
      corepop seeds and SHA256SUMS), and the curl one-liner is verified
      end-to-end on both platforms. Remaining refinement: linux-aarch64 /
      riscv64 tarballs, and a CI job per platform so every release ships
      fresh assets instead of hand-built uploads.
- [ ] **Nix path** (0.5–1 day) — teach `popsession` the Nix store layout
      (today it requires `./poplog` + `./target/pop/basepop11`; the flake's
      out-path differs), then `nix profile install github:IoTone/poplog#poplog`
      + `install.sh` just works; later a `#pop11-skill` flake output that
      does both.
- [ ] **Homebrew tap** (1–2 days, optional) — `brew install iotone/tap/poplog`
      wrapping the tarball; reaches the largest macOS audience.
- [ ] Installer polish: `--uninstall`, version pinning, upgrade-in-place,
      CI job that runs install.sh + smoke on macOS and Linux runners.
