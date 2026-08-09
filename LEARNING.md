# Learning Poplog — fetching the classic teaching material

Four decades of Pop-11 and Prolog teaching material — university course
packs, TEACH files, and classic AI toolkits — survive in public archives.
This repository does **not** vendor any of it; instead a small script
downloads it on demand:

```sh
tools/fetch-learning.sh list        # what's available
tools/fetch-learning.sh --all       # fetch everything (~30 MB)
tools/fetch-learning.sh bhamteach hidden-gems   # or pick packs
```

Content lands in `learn/<pack>/` (gitignored).  Each pack records its
origin in `learn/<pack>/.source` (URL, date, git commit or SHA-256).
Upstream licences apply to each pack — this repo distributes only the
fetch script.

## Using it

Fetching regenerates `learn/learn.p`, which extends Poplog's search
lists (`vedteachlist`, `vedhelplist`, `vedreflist`, `popuseslist`,
`popautolist`) so the material works like the built-in documentation:

```
$ pop11
: load learn/learn.p;           ;;; or add this line to $poplib/init.p
: teach respond                 ;;; Birmingham chatbot tutorial, in ved
: uses prblib;                  ;;; Poprulebase, straight off popuseslist
```

Standalone examples run directly, e.g.
`pop11 learn/hidden-gems/01_open_stack/fact.p`.

## The packs

| Pack | Source | What it is |
| --- | --- | --- |
| `hidden-gems` | [sfkleach/hidden-gems-of-pop11](https://github.com/sfkleach/hidden-gems-of-pop11) (CC0) | Small idiomatic demos of what makes Pop-11 special: the open stack, updaters, dynamic lists, coroutines, dlocals, GC, extensible syntax |
| `bhamteach` | [Poplog Archive](https://poplogarchive.getpoplog.org/) | The Birmingham introductory-AI course TEACH files — pattern-matching chatbots (`teach respond`), grammars and parsing, story generation, recursion exercises |
| `examples` | [GetPoplog/examples](https://github.com/GetPoplog/examples) | Teaching examples curated from the Poplog Archive: Othello, Life, robolang, kinds of programming |
| `packages` | [hebisch/poplog_packages](https://github.com/hebisch/poplog_packages) | The classic package tree: **newkit** (SimAgent + Poprulebase — the Birmingham agent-architectures toolkit with full TEACH/HELP trees), **popvision** (David Young's vision + neural-net tutorials), **rclib**/**rcmenu** (graphics), **neural**, **brait** (Braitenberg vehicles), **teaching** |
| `paradigms` | [GetPoplog/paradigms_lectures](https://github.com/GetPoplog/paradigms_lectures) | A UMASS programming-language-paradigms course taught in Pop-11 (1997–2000) |
| `primer` | Poplog Archive | The Pop-11 Primer (PDF) — the standard "learn Pop-11" text for experienced programmers |
| `screamer` | Poplog Archive | Constraint programming / nondeterministic search package |

**Prolog:** the richest Prolog material is already in-tree — `teach prolog`
and the `pop/plog/` subsystem ship with this repository.  The packs above
add Prolog-adjacent material: Poprulebase (forward-chaining rules) and the
bhamteach course notes.

## Writing your own libraries — TEACH JSON

Alongside the fetched material, this repository vendors an original
learning module: **`teach json`** (`pop/teach/json`) walks through the
design and construction of **`lib json`** (`pop/lib/lib/json.p`), the
JSON parser/generator added in this fork, as a case study in creating a
new Poplog library — data-mapping design, recursive descent, open-stack
string building (including a real bug and its lesson), `dlocal`
re-entrancy, sections/exports, must-fail testing, and when to vendor vs.
fetch.  Reference documentation is in `help json`; the acceptance suite
is `tools/test-json.sh`.

## Provenance notes

The original home of most of this material, Aaron Sloman's Birmingham
"Free Poplog" site (`www.cs.bham.ac.uk/research/projects/poplog/`), now
redirects permanently to the [Poplog Archive](https://poplogarchive.getpoplog.org/)
maintained by the [GetPoplog](https://github.com/GetPoplog) project; the
script fetches from the archive and from GitHub mirrors.  Some historic
tarballs (`newkit.tar.gz`, `popvision.tar.gz`, `rclib.tar.gz`) are no
longer served at their old paths — the `packages` pack covers that
content from the git mirror instead.

Graphics-based material (rclib, some SimAgent demos) was written against
X/Motif; on this fork much of `rc_graphic` also runs on the native
graphics backend (see "Native graphics" in the README), but X-specific
TEACH files may need adaptation.
