# laya — typed decisions from Pop-11, answered locally

`lib laya` makes [`lib typesafe`](../typesafe/README.md)'s `ts_eval` answer with
[Laya](https://github.com/mizorewww/laya-mlx), an open-weight decision model, running on
this Mac's GPU through MLX. No key, no network after the first download, about 10 ms a
question.

**This is not part of the Poplog release.** Like `typesafe`, it is an out-of-tree
library.

## Why it needs no new API

Laya takes the request the hosted `POST /v1/systemone` takes (state plus a map of
`noul`/`choice`/`score` questions) and returns the same answers. So the call site does
not change. `uses laya` replaces `ts_transport` with one that talks to a
`laya-mlx serve --stdio` child process over a pipe:

```pop11
uses laya;      ;;; loads typesafe too, and installs the local transport

lvars answers = ts_eval('I was billed twice. Please refund the duplicate.',
    [[team   ^(ts_choice('Who should handle this?',
                         [[billing false] [technical false] [sales false]]))]
     [refund ^(ts_noul('Does the customer ask for money back?', false, false))]]);

answers('team')('choice') =>            ** billing
answers('team')('probabilities')('billing') =>   ** 0.8893
answers('refund')('noul') =>            ** 0.8355
ts_last_model =>   ** aac6fef/laya-mlx@20aed815fc6acde75733882e7ec0e3f28aeb9717 float16
```

`ts_last_model` names the exact checkpoint commit and precision. Record it beside any
result you keep, because both change probabilities.

Why a child process rather than HTTP or loading MLX into Poplog:

* **No port.** Nothing listens, so nothing on the network can use the model.
* **Its lifetime is Poplog's.** When Poplog exits the pipe closes, and the server exits
  at end of input.
* **A crash stays over there.** If the model process dies mid-call, that call mishaps and
  the next one starts a fresh child (see *Tests*).
* **The cost is small.** Measured: the pipe and JSON add **0.16 ms** to a ~10 ms answer.
  A loopback HTTP server adds 0.54 ms, and that cost is in the server, not in Pop-11.

## Install

```sh
pip install laya-mlx            # Apple Silicon, macOS 14+, Python 3.11+
mkdir -p "$poplogroot/local/auto"
cp packages/typesafe/typesafe.p packages/laya/laya.p "$poplogroot/local/auto/"
```

The first call downloads the checkpoint (about 0.9 GB) and loads it. Later starts take a
couple of seconds. `laya_start()` is called for you on first use. Call it yourself to take
that wait at a moment you choose.

Without installing:

```pop11
extend_searchlist('packages/typesafe', popuseslist) -> popuseslist;
extend_searchlist('packages/laya', popuseslist) -> popuseslist;
uses laya;
```

If `laya-mlx` is not on `$PATH` (in a virtualenv, say), point at it:

```sh
export LAYA_MLX=/path/to/venv/bin/laya-mlx
```

## Settings

| variable | default | |
| --- | --- | --- |
| `laya_command` | `$LAYA_MLX` or `'laya-mlx'` | searched on `$PATH` unless it starts with `/` |
| `laya_model` | `'aac6fef/laya-mlx'` | Hub id or local directory; `aac6fef/laya-multilingual-mlx` for non-English text |
| `laya_router` | `false` | `true`: choose a checkpoint per call by language, keeping all three loaded |
| `laya_dtype` | `'float16'` | `'float32'` for closer agreement with the reference |
| `laya_extra_args` | `[]` | passed to `laya-mlx serve`, e.g. `['--device' 'cpu']` |

Settings are read when the child starts. To change them, call `laya_stop()`, then the
next call starts a new child.

| procedure | |
| --- | --- |
| `laya_start()` / `laya_stop()` | start the child now (waiting for the model to load) / stop it |
| `laya_running()`, `laya_pid()` | |
| `laya_health()` | property with `'status'` and `'model'` |
| `laya_install()` / `laya_uninstall()` | point `ts_eval` here / back at the hosted API |

## What differs from the hosted model

* **Different model, same schema.** Laya and Jev are different models. Their numbers are
  not comparable, and calibrations differ.
* **`output_tokens` is always 0.** Laya generates nothing, so it answers in a single
  forward pass.
* **Answers carry more.** Every answer has `probabilities` and `action`, and a `score`
  answer has `legend`. Read them like any other field.
* **Order matters, so it is kept.** Laya reads choice options as a sequence, and on one
  checkpoint reordering three options changed the pick in 5 of 6 orderings. `ts_choice`
  therefore sends options in the order you wrote them, and `ts_request` keeps question
  order too. This needed `json_object` in `LIB JSON`, which keeps insertion order.
* **No timeout.** A call blocks until the model answers. `ts_timeout` does not apply.

## Tests

```sh
sh tools/test-libs.sh packages/laya/tests/test_laya.p
```

21 checks, with no model and no MLX. `tests/fake_laya_server.py` speaks the same
protocol with canned answers, and can be told to fail. The checks cover:

* answers through `ts_eval`
* options arriving in written order
* a 422 that keeps the child
* a crash mid-call that forgets it and restarts on the next call
* install and uninstall
* a missing command

Against the real model, the laya-mlx repository's `experiments/poplog/` checks three
things:

* **Same answers as Python.** The validation fixtures through `ts_eval` match Python's
  `Agent.predict` field for field: 63 questions × 3 checkpoints × FP16/FP32, all 2,868
  fields identical.
* **Robustness.** 10,000 sequential calls on one child; a malformed question; `kill -9`
  mid-call.
* **Latency.** A paired measurement of the transport cost.
