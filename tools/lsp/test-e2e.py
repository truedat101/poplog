#!/usr/bin/env python3
"""End-to-end test of the Pop-11 LSP server over the real protocol.

Drives tools/pop11-lsp as an editor would: initialize, open a document
with a syntax error (expect a diagnostic on the right line), replace it
with a clean version (expect the diagnostic to clear), hover a stdlib
word (expect HELP text), ask for completions, shut down.

    python3 tools/lsp/test-e2e.py
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = os.path.join(REPO, "tools", "pop11-lsp")

failures = []


def check(name, ok, detail=""):
    print(("PASS  " if ok else "FAIL  ") + name + (f"  ({detail})" if detail and not ok else ""))
    if not ok:
        failures.append(name)


class Lsp:
    def __init__(self):
        self.proc = subprocess.Popen(
            [SERVER], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        self.next_id = 1
        self.pending = []          # server->client messages not yet consumed

    def send(self, method, params, request=True):
        msg = {"jsonrpc": "2.0", "method": method, "params": params}
        if request:
            msg["id"] = self.next_id
            self.next_id += 1
        body = json.dumps(msg).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.proc.stdin.flush()
        return msg.get("id")

    def read_message(self, timeout=30):
        import select
        headers = {}
        line = b""
        # naive blocking reads; the subprocess pipe is line-buffered enough
        while True:
            line = self.proc.stdout.readline()
            if not line:
                return None
            line = line.strip()
            if not line:
                break
            if b":" in line:
                k, v = line.split(b":", 1)
                headers[k.strip().lower()] = v.strip()
        n = int(headers[b"content-length"])
        return json.loads(self.proc.stdout.read(n))

    def wait_for(self, pred, tries=20):
        for m in self.pending:
            if pred(m):
                self.pending.remove(m)
                return m
        for _ in range(tries):
            m = self.read_message()
            if m is None:
                return None
            if pred(m):
                return m
            self.pending.append(m)
        return None

    def request(self, method, params):
        rid = self.send(method, params, request=True)
        return self.wait_for(lambda m: m.get("id") == rid)

    def notify(self, method, params):
        self.send(method, params, request=False)


def main():
    lsp = Lsp()
    uri = "file:///tmp/lsp-e2e.p"

    # --- initialize -----------------------------------------------------
    r = lsp.request("initialize", {"processId": os.getpid(), "capabilities": {}})
    caps = (r or {}).get("result", {}).get("capabilities", {})
    check("initialize", bool(r), repr(r))
    check("sync full", caps.get("textDocumentSync") == 1, repr(caps))
    check("hover cap", caps.get("hoverProvider") is True)
    check("completion cap", "completionProvider" in caps)
    lsp.notify("initialized", {})

    # --- didOpen with a syntax error on line 3 (0-based: 2) -------------
    # (an `endif` with no `if` is a real MISPLACED EXPRESSION ITEM;
    # itemiser lookahead may report one line beyond it)
    bad = "vars x = 1;\n;;; comment\nx endif;\n"
    lsp.notify("textDocument/didOpen", {
        "textDocument": {"uri": uri, "languageId": "pop11",
                         "version": 1, "text": bad}})
    m = lsp.wait_for(lambda m: m.get("method") == "textDocument/publishDiagnostics")
    diags = (m or {}).get("params", {}).get("diagnostics", [])
    check("bad code -> diagnostic", len(diags) == 1, repr(m))
    if diags:
        check("diagnostic line", diags[0]["range"]["start"]["line"] in (2, 3),
              repr(diags[0]["range"]))
        check("diagnostic message", bool(diags[0]["message"].strip()))

    # --- didChange to clean code -> diagnostics clear -------------------
    good = "vars x = 1;\ndefine f(y); y * 2 enddefine;\n"
    lsp.notify("textDocument/didChange", {
        "textDocument": {"uri": uri, "version": 2},
        "contentChanges": [{"text": good}]})
    m = lsp.wait_for(lambda m: m.get("method") == "textDocument/publishDiagnostics")
    diags = (m or {}).get("params", {}).get("diagnostics", [])
    check("clean code -> no diagnostics", diags == [], repr(diags))

    # --- unclosed comment -> structural diagnostic ----------------------
    lsp.notify("textDocument/didChange", {
        "textDocument": {"uri": uri, "version": 3},
        "contentChanges": [{"text": "/* never closed\nvars y = 2;\n"}]})
    m = lsp.wait_for(lambda m: m.get("method") == "textDocument/publishDiagnostics")
    diags = (m or {}).get("params", {}).get("diagnostics", [])
    check("unclosed comment flagged", len(diags) == 1 and
          "comment" in diags[0]["message"], repr(diags))

    # --- hover over a stdlib word ---------------------------------------
    hover_doc = "npr([1 2 3]);\n"
    lsp.notify("textDocument/didChange", {
        "textDocument": {"uri": uri, "version": 4},
        "contentChanges": [{"text": hover_doc}]})
    lsp.wait_for(lambda m: m.get("method") == "textDocument/publishDiagnostics")
    r = lsp.request("textDocument/hover", {
        "textDocument": {"uri": uri},
        "position": {"line": 0, "character": 1}})   # inside 'npr'
    result = (r or {}).get("result")
    check("hover npr -> HELP text",
          bool(result) and "npr" in result["contents"]["value"].lower(),
          repr(r)[:200])

    # --- hover over gibberish -> null -----------------------------------
    r = lsp.request("textDocument/hover", {
        "textDocument": {"uri": uri},
        "position": {"line": 0, "character": 6}})   # inside '[1 2 3]'
    check("hover nothing -> null", (r or {}).get("result") is None, repr(r))

    # --- completion ------------------------------------------------------
    comp_doc = "syssle\n"
    lsp.notify("textDocument/didChange", {
        "textDocument": {"uri": uri, "version": 5},
        "contentChanges": [{"text": comp_doc}]})
    lsp.wait_for(lambda m: m.get("method") == "textDocument/publishDiagnostics")
    r = lsp.request("textDocument/completion", {
        "textDocument": {"uri": uri},
        "position": {"line": 0, "character": 6}})
    items = ((r or {}).get("result") or {}).get("items", [])
    labels = [i["label"] for i in items]
    check("completion syssle -> syssleep", "syssleep" in labels, repr(labels)[:200])

    # --- server survives a garbage request ------------------------------
    r = lsp.request("workspace/executeCommand", {"command": "nope"})
    check("unknown method -> error", bool(r and r.get("error")), repr(r))

    # --- shutdown --------------------------------------------------------
    r = lsp.request("shutdown", {})
    check("shutdown", bool(r) and r.get("result") is None, repr(r))
    lsp.notify("exit", {})
    try:
        lsp.proc.wait(timeout=10)
        check("clean exit", lsp.proc.returncode == 0,
              f"rc={lsp.proc.returncode}")
    except subprocess.TimeoutExpired:
        lsp.proc.kill()
        check("clean exit", False, "timeout")

    print()
    if failures:
        print(f"SUMMARY: {len(failures)} FAILURES: {failures}")
        sys.exit(1)
    print("SUMMARY: ALL PASS")


if __name__ == "__main__":
    main()
