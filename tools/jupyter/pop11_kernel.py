#!/usr/bin/env python3
"""pop11_kernel -- a Jupyter kernel for Pop-11 (Poplog).

2030plan item 1.3: a THIN adapter. All the hard parts of keeping a live
Pop-11 engine attached to a conversation -- the FIFO stdin, sentinel
framing, mishap survival, checkpoint/restore -- are already solved and
field-proven in the pop11 skill's `popsession`, so each cell is one
`popsession send`. The session persists for the kernel's lifetime:
define a procedure in one cell (compiled to native code) and call it
from any later cell.

The kernelspec (written by install-kernel.sh) sets POP11_SESSION_BIN to
the popsession executable.
"""

import os
import subprocess
import tempfile

from ipykernel.kernelbase import Kernel

RAINBOW = "\U0001F308"          # popsession's per-send timing line
ERRMARK = "__ERROR__"           # popsession's mishap marker


class Pop11Kernel(Kernel):
    implementation = "pop11"
    implementation_version = "0.1.0"
    language = "pop11"
    language_version = "16.2"
    language_info = {
        "name": "pop11",
        "file_extension": ".p",
        "mimetype": "text/x-pop11",
        "pygments_lexer": "text",
    }
    banner = (
        "Pop-11 (Poplog) — one persistent session, incrementally compiled "
        "to native code. Defines survive between cells."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.popsession = os.environ.get(
            "POP11_SESSION_BIN",
            os.path.expanduser("~/.claude/skills/pop11/bin/popsession"),
        )
        self.session_name = "jupyter%d" % os.getpid()
        self._started = False

    # -- session management -------------------------------------------------

    def _run(self, *args, timeout=180):
        return subprocess.run(
            [self.popsession, *args, "--name", self.session_name],
            capture_output=True, text=True, timeout=timeout,
        )

    def _ensure_session(self):
        if self._started:
            return None
        r = self._run("start")
        if r.returncode != 0:
            return (r.stdout or "") + (r.stderr or "")
        self._started = True
        return None

    # -- protocol -----------------------------------------------------------

    def do_execute(self, code, silent, store_history=True,
                   user_expressions=None, allow_stdin=False,
                   *, cell_meta=None, cell_id=None):
        boot_err = self._ensure_session()
        if boot_err is not None:
            self._stream("stderr", "could not start the Pop-11 session:\n" + boot_err)
            return self._reply("error", "session-start-failed")

        if not code.strip():
            return self._reply("ok")

        with tempfile.NamedTemporaryFile(
                "w", suffix=".p", delete=False) as f:
            f.write(code if code.endswith("\n") else code + "\n")
            spool = f.name
        try:
            r = self._run("send", "-f", spool)
        finally:
            os.unlink(spool)

        mishap = r.returncode != 0
        if mishap and "TIMEOUT" in (r.stdout or ""):
            # the engine is still stuck in that chunk: restart the session
            # so later cells get a live engine (state is lost — say so).
            try:
                self._run("stop", timeout=30)
            except Exception:
                pass
            self._started = False
            self._ensure_session()
            self._stream(
                "stderr",
                "cell timed out; the Pop-11 session was restarted "
                "(session state reset)\n")
        out_lines, timing = [], None
        for line in (r.stdout or "").splitlines():
            if line.startswith(RAINBOW):
                timing = line
            elif line.strip() == ERRMARK:
                pass
            else:
                out_lines.append(line)

        if not silent:
            if out_lines:
                self._stream("stderr" if mishap else "stdout",
                             "\n".join(out_lines) + "\n")
            if r.stderr:
                self._stream("stderr", r.stderr)
            if timing and not mishap:
                self._stream("stdout", timing + "\n")

        if mishap:
            # the diagnostics were already streamed; keep the error object small
            content = {
                "ename": "mishap",
                "evalue": (out_lines or ["Pop-11 mishap"])[-1][:120],
                "traceback": [],
            }
            self.send_response(self.iopub_socket, "error", content)
            return self._reply("error", content["ename"],
                               evalue=content["evalue"])
        return self._reply("ok")

    def do_shutdown(self, restart):
        if self._started:
            try:
                self._run("stop", timeout=30)
            except Exception:
                pass
            self._started = False
        return {"status": "ok", "restart": restart}

    def do_is_complete(self, code):
        return {"status": "complete"}

    # -- helpers ------------------------------------------------------------

    def _stream(self, name, text):
        self.send_response(self.iopub_socket, "stream",
                           {"name": name, "text": text})

    def _reply(self, status, ename=None, evalue=None):
        reply = {
            "status": status,
            "execution_count": self.execution_count,
            "payload": [],
            "user_expressions": {},
        }
        if status == "error":
            reply["ename"] = ename or "error"
            reply["evalue"] = evalue or ""
            reply["traceback"] = []
        return reply


if __name__ == "__main__":
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=Pop11Kernel)
