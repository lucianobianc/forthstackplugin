#!/usr/bin/env python3
"""Compile-time probes for Gforth 0.7.3. No dependencies beyond Python 3."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import signal
import sys
import tempfile

ENGINE = Path(__file__).with_name("trace.fs")
PHASES = {0: "before", 1: "after", 2: "entry", 3: "return"}


def parse_trace(raw):
    """Validate framing before exposing snapshots; never infer a missing result."""
    if raw and not raw.endswith("\n"):
        raise ValueError("truncated record")
    sites, events, result = {}, [], None
    for line in raw.splitlines():
        fields = line.split()
        if not fields:
            continue
        if result is not None:
            raise ValueError("records after result marker")
        if fields[0] == "M" and len(fields) == 8:
            site, lineno, column = map(int, fields[1:4])
            if site in sites or site <= 0 or lineno < 1 or column < 1:
                raise ValueError("invalid source location")
            filename, token, word = (bytes.fromhex(x).decode("utf-8", "replace")
                                     for x in fields[4:7])
            sites[site] = {"file": filename, "line": lineno,
                           "column_bytes": column, "token": token, "word": word,
                           "coverage": fields[7]}
            if fields[7] not in ("probe", "opaque"):
                raise ValueError("invalid coverage marker")
        elif fields[0] == "E" and len(fields) >= 5:
            seq, site, phase, depth = map(int, fields[1:5])
            stack = list(map(int, fields[5:]))
            if (seq != len(events) or phase not in PHASES or depth != len(stack)
                    or (site == 0) != (phase in (2, 3))
                    or (site != 0 and site not in sites)):
                raise ValueError("invalid event framing")
            events.append({"seq": seq, "site": site, "phase": PHASES[phase],
                           "source": sites.get(site), "stack": stack})
        elif fields[0] == "X" and len(fields) == 2:
            result = int(fields[1])
        else:
            raise ValueError("invalid or partial record")
    if result == 0 and (not events or events[0]["phase"] != "entry"
                        or events[-1]["phase"] != "return"):
        raise ValueError("successful run without entry/return")
    return sites, events, result


def trace(source, entry, *, gforth="gforth", inputs=(), timeout=5,
          max_events=10000, max_depth=256):
    source = Path(source).resolve(strict=True)
    if timeout <= 0 or max_events < 1 or max_depth < 1:
        raise ValueError("limits must be positive")
    if not entry or any(c.isspace() for c in entry):
        raise ValueError("entry must be a single Forth name")
    # Integers are serialized, never accept executable Forth in the CLI inputs.
    invocation = " ".join(str(int(n)) for n in inputs)
    command = [gforth, str(ENGINE), "-e",
               f"{max_events} fst-limit ! {max_depth} fst-max-depth ! "
               f":noname {invocation} ; is fst-inputs fst-run bye"]
    with tempfile.TemporaryDirectory(prefix="forth-stack-") as temporary:
        raw_path = Path(temporary) / "events.txt"
        environment = dict(os.environ, FST_SOURCE=str(source), FST_ENTRY=entry,
                           FST_TRACE=str(raw_path))
        status, diagnostic = "ok", None
        process = subprocess.Popen(command, env=environment, cwd=source.parent,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        try:
            captured_out, captured_err = process.communicate(timeout=timeout)
            stdout = captured_out.decode("utf-8", "replace")
            stderr = captured_err.decode("utf-8", "replace")
            returncode = process.returncode
            if returncode:
                status = "process_error"
        except subprocess.TimeoutExpired as error:
            status, diagnostic, returncode = "timeout", "execution timed out", None
            stdout = (error.stdout or b"").decode("utf-8", "replace")
            stderr = (error.stderr or b"").decode("utf-8", "replace")
        finally:
            # Also runs when the Neovim parent cancels this supervisor with SIGTERM.
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()
        raw = raw_path.read_text() if raw_path.exists() else ""
    try:
        sites, events, result = parse_trace(raw)
    except ValueError as error:
        sites, events, result = {}, [], None
        if status == "ok":
            status = "protocol_error"
        diagnostic = str(error)
    if status == "ok":
        if result is None:
            status, diagnostic = "incomplete", "missing result marker"
        elif result != 0:
            status = "forth_error"
            diagnostic = {-4096: "event limit exceeded",
                          -4097: "stack depth limit exceeded"}.get(result, "Forth THROW")
    return {"format_version": 1, "status": status, "complete": status == "ok",
            "source": str(source), "entry": entry, "forth_code": result,
            "process_returncode": returncode, "diagnostic": diagnostic,
            "sites": sites, "events": events, "stdout": stdout, "stderr": stderr}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("entry")
    parser.add_argument("--gforth", default="gforth")
    parser.add_argument("--input", type=int, action="append", default=[])
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("--max-events", type=int, default=10000)
    parser.add_argument("--max-depth", type=int, default=256)
    args = parser.parse_args()
    try:
        result = trace(args.source, args.entry, gforth=args.gforth, inputs=args.input,
                       timeout=args.timeout, max_events=args.max_events,
                       max_depth=args.max_depth)
    except (OSError, ValueError) as error:
        parser.exit(2, f"trace: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["complete"] else 1


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda number, frame: sys.exit(128 + number))
    raise SystemExit(main())
