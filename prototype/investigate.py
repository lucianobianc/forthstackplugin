#!/usr/bin/env python3
"""Reproduce the native Gforth debugger experiments (not the tracer tests)."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gforth", default="gforth")
    parser.add_argument("--gforth-itc", help="Optional indirect-threaded engine")
    args = parser.parse_args()
    probes = [
        ("see", args.gforth, ": sample 15 1+ ; see sample bye", b""),
        ("stack", args.gforth, ": sample 15 .s 1+ .s ; sample bye", b""),
        ("source-marker", args.gforth, ": sample 15 ~~ 1+ ~~ ; sample bye", b""),
        ("dbg-default", args.gforth, ": sample 15 1+ ; dbg sample .s bye", b"    "),
    ]
    probes.append(("uncaught-throw", args.gforth,
                   ": fail -77 throw ; fail bye", b""))
    if args.gforth_itc:
        probes.append(("dbg-itc", args.gforth_itc,
                       ": sample 15 1+ ; dbg sample .s bye", b"    "))
        probes.append(("break-itc", args.gforth_itc,
                       ": sample 15 break: 1+ ; sample .s bye", b"    "))
    results = []
    with tempfile.TemporaryDirectory(prefix="gforth-investigation-") as temporary:
        for name, engine, code, stdin in probes:
            source = Path(temporary) / (name + ".fs")
            source.write_text(code + "\n")
            try:
                process = subprocess.run([engine, str(source)], input=stdin,
                                         capture_output=True, timeout=5, cwd=temporary)
                results.append({"probe": name, "returncode": process.returncode,
                                "stdout": process.stdout.decode("utf-8", "replace"),
                                "stderr": process.stderr.decode("utf-8", "replace")})
            except subprocess.TimeoutExpired:
                results.append({"probe": name, "error": "timeout"})
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
