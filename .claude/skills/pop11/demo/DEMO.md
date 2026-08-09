# Monday demo: Pop-11 as a live scripting engine for Claude

**The pitch (30 s).** Assistants script in Python today: every task pays
interpreter startup, imports, and re-definition — and all state dies with the
process. This skill gives Claude a **retained Pop-11 session**: helpers are
compiled to native machine code once, every later task costs ~1 ms, errors
can't kill the session, and the whole session — state *and* compiled code —
checkpoints to a ~200 KB file that restores in 8 ms. Live numbers:
`tools/bench-skill/README.md` (16× vs cold Python per task; redefinition to
native code in 60 µs).

**Prep (before the demo):**

```sh
export POPLOG_ROOT=/Users/dkords/dev/projects/truedat101/poplog   # built tree
PATH="$PWD/.claude/skills/pop11/bin:$PATH"
popsession stop 2>/dev/null; rm -f /tmp/demo.psv
build-popcurl                                    # pre-build the HTTPS shim
```

## Beat 1 — a session that remembers (60 s)

```sh
popsession start
popsession send -c "
define nfib(n); if n < 2 then 1 else nfib(n-1) + nfib(n-2) + 1 endif enddefine;
vars ncalls = 0;
npr('helper compiled to native code');"

popsession send -c "ncalls + 1 -> ncalls; npr('call ' sys_>< ncalls sys_>< ': ' sys_>< nfib(25));"
popsession send -c "ncalls + 1 -> ncalls; npr('call ' sys_>< ncalls sys_>< ': ' sys_>< nfib(25));"
```

*Say:* each `send` is a separate shell process — the counter proves the
session persists between tool calls. `nfib` ran as machine code, not
interpretation.

## Beat 2 — errors don't kill it; redefinition is live (45 s)

```sh
popsession send -c "npr(1 + oops_not_defined);"    # mishap, exit code 1
popsession send -c "npr('still alive: ' sys_>< nfib(10));"
popsession send -c "define nfib(n); if n < 2 then 2 else nfib(n-1)+nfib(n-2)+1 endif enddefine;
npr('redefined live: ' sys_>< nfib(10));"
```

*Say:* the mishap printed full diagnostics and the session survived. The
redefinition recompiled to native code in ~60 microseconds, mid-session.

## Beat 3 — checkpoint / restore: the killer feature (60 s)

```sh
popsession checkpoint /tmp/demo.psv
popsession send -c "999 -> ncalls; npr('state vandalised');"
popsession stop
ls -la /tmp/demo.psv                                # ~200 KB
popsession restore /tmp/demo.psv
popsession send -c "npr('back from the dead: ncalls=' sys_>< ncalls);"
```

*Say:* the restore took milliseconds and brought back the heap AND the
compiled procedures — pre-vandalism. Warm Python cannot do this; a Jupyter
kernel dies with the machine. This is "resume yesterday's session."

## Beat 4 — real work: HTTPS + processing in one session (60 s)

```sh
popsession send -c "load '$HOME/.cache/pop11-skill/popcurl.p';
npr(curl_version_string());
npr('GET -> ' sys_>< http_get('https://example.com/', '/tmp/page.html'));"

popsession send -c "
vars rep = line_repeater(sysopen('/tmp/page.html', 0, \"line\"), inits(4096));
vars line, n = 0;
repeat rep() -> line; quitif(line == termin);
    if issubstring('href', 1, line) then n + 1 -> n endif;
endrepeat;
npr('link lines: ' sys_>< n);"
```

*Say:* that HTTPS call is Pop-11 calling the system libcurl through a
20-line C shim, loaded at runtime — no rebuild. The fetch and the analysis
share one session.

## Beat 5 — the numbers (30 s)

Show `tools/bench-skill/README.md` table: py-cold 23 ms/task vs pop-warm
1.4 ms; modelled hour 2.8 s vs 0.2 s; saved-image restore 7.8 ms. *Close:*
"the goal isn't shaving milliseconds — it's an assistant that accumulates
compiled, checkpointable capability over a session instead of starting from
zero on every tool call."

## If something goes sideways

- `popsession status` — is it alive? `popsession stop` + `start` resets in ~1 s.
- Session state lives in `~/.cache/pop11-skill/session-default/` (`out.log`
  has everything the engine ever printed).
- No network? Skip Beat 4's GET; `http_get` on a `file://` URL also works.
- All beats were run end-to-end on this machine on 2026-07-31.
