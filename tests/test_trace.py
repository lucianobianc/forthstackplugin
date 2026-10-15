import hashlib
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("forth_trace", ROOT / "prototype/trace.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
GFORTH = os.environ.get("GFORTH", "gforth")


class TraceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "source.fs"

    def run_source(self, text, entry="sample", **kwargs):
        self.source.write_text(text)
        digest = hashlib.sha256(self.source.read_bytes()).digest()
        result = module.trace(self.source, entry, gforth=GFORTH, **kwargs)
        self.assertEqual(digest, hashlib.sha256(self.source.read_bytes()).digest())
        return result

    def successful(self, result, stack):
        self.assertEqual(result["status"], "ok", result)
        self.assertTrue(result["complete"])
        self.assertEqual(result["events"][-1]["stack"], stack)
        self.assertEqual([e["seq"] for e in result["events"]],
                         list(range(len(result["events"]))))

    def test_nested_compiled_word_and_original_source_positions(self):
        result = module.trace(ROOT / "examples/compiled.fs", "example", gforth=GFORTH)
        self.successful(result, [21])
        increment = [e for e in result["events"] if e["source"]
                     and e["source"]["word"] == "birthday"]
        self.assertEqual([(e["phase"], e["stack"]) for e in increment],
                         [("before", [15]), ("after", [16])])
        self.assertEqual(increment[0]["source"]["line"], 3)
        self.assertEqual(increment[0]["source"]["column_bytes"], 3)
        lines = (ROOT / "examples/compiled.fs").read_bytes().splitlines()
        for site in result["sites"].values():
            token = site["token"].encode()
            self.assertEqual(lines[site["line"] - 1][site["column_bytes"] - 1:]
                             [:len(token)], token)
        # False branch executes; the source map still includes the untaken branch.
        self.assertFalse(any(e["source"] and e["source"]["line"] == 10
                             for e in result["events"]))
        iterations = [e["stack"][-1] for e in result["events"]
                      if e["source"] and e["source"]["token"] == "i"
                      and e["phase"] == "after"]
        self.assertEqual(iterations, [0, 1, 2])

    def test_both_conditional_paths(self):
        for value, expected in [(0, 22), (-1, 11)]:
            with self.subTest(value=value):
                result = self.run_source(": sample if 11 else 22 then ;",
                                         inputs=[value])
                self.successful(result, [expected])
                executed = [e["source"]["token"] for e in result["events"]
                            if e["source"]]
                self.assertNotIn(str(33 - expected), executed)

    def test_stack_permutations_and_native_execution_agree(self):
        text = ": sample 1 2 swap over rot dup nip tuck drop + ;"
        result = self.run_source(text)
        process = subprocess.run([GFORTH, str(self.source), "-e", "sample .s bye"],
                                 check=True, capture_output=True, text=True)
        plain_stack = list(map(int, re.search(r"<\d+>\s*(.*)", process.stdout)[1].split()))
        self.successful(result, plain_stack)
        for before, after in zip(result["events"][1::2], result["events"][2::2]):
            self.assertEqual(before["site"], after["site"])

    def test_return_stack_words_and_loop_parameters(self):
        result = self.run_source(": sample 7 >r 2 r> + 3 0 do i + loop ;")
        self.successful(result, [12])

    def test_recursion_and_exit(self):
        result = self.run_source(": sample dup 0= if exit then 1- recurse ;", inputs=[3])
        self.successful(result, [0])
        self.assertEqual(sum(e["source"] is not None and e["source"]["token"] == "1-"
                             and e["phase"] == "after" for e in result["events"]), 3)

    def test_base_and_pictured_numeric_output_are_preserved(self):
        result = self.run_source(
            ': sample [ hex ] ff [ decimal ] hex decimal 123 0 <# #s #> type ;')
        self.successful(result, [255])
        self.assertEqual(result["stdout"], "123")

    def test_signed_cell_minimum_and_multiple_inputs(self):
        result = self.run_source(": sample swap ;", inputs=[-9223372036854775808, 2])
        self.successful(result, [2, -9223372036854775808])

    def test_strings_and_immediates_have_explicit_opaque_coverage(self):
        result = self.run_source(': sample s" hello" type 9 ;')
        self.successful(result, [9])
        self.assertEqual(result["stdout"], "hello")
        opaque = [s["token"] for s in result["sites"].values() if s["coverage"] == "opaque"]
        self.assertIn('s"', opaque)
        self.assertIn(';', opaque)

    def test_include_maps_helper_to_its_own_file(self):
        helper = Path(self.directory.name) / "helper.fs"
        helper.write_text(": helper 1+ ;")
        result = self.run_source("include helper.fs\n: sample 15 helper ;")
        self.successful(result, [16])
        events = [e for e in result["events"] if e["source"]
                  and e["source"]["word"] == "helper"]
        self.assertEqual(Path(events[0]["source"]["file"]), helper)

    def test_throw_preserves_partial_trace_without_false_return(self):
        result = self.run_source(": sample 15 -77 throw 99 ;")
        self.assertEqual(result["status"], "forth_error")
        self.assertEqual(result["forth_code"], -77)
        self.assertFalse(result["complete"])
        self.assertNotIn("return", [e["phase"] for e in result["events"]])
        self.assertEqual(result["events"][-1]["source"]["token"], "throw")
        self.assertEqual(result["events"][-1]["phase"], "before")

    def test_compile_failure_and_unknown_entry(self):
        result = self.run_source(": sample missing-word ;")
        self.assertEqual(result["status"], "forth_error")
        self.assertEqual(result["forth_code"], -13)
        self.assertEqual(result["events"], [])
        result = self.run_source(": other 1 ;")
        self.assertEqual(result["forth_code"], -13)
        self.assertFalse(result["complete"])

    def test_event_limit(self):
        result = self.run_source(": sample 0 begin 1+ again ;", max_events=6)
        self.assertEqual(result["status"], "forth_error")
        self.assertEqual(result["forth_code"], -4096)
        self.assertEqual(len(result["events"]), 6)

    def test_depth_limit(self):
        result = self.run_source(": sample 1 dup dup ;", max_depth=2)
        self.assertEqual(result["forth_code"], -4097)
        self.assertFalse(result["complete"])

    def test_timeout_and_premature_bye(self):
        result = self.run_source(": sample begin again ;", timeout=0.2)
        self.assertEqual(result["status"], "timeout")
        self.assertFalse(result["complete"])
        result = self.run_source(": sample bye ;")
        self.assertEqual(result["status"], "incomplete")
        self.assertFalse(result["complete"])

    def test_unsaved_snapshot_keeps_source_identity_and_relative_include(self):
        helper = Path(self.directory.name) / "helper.fs"
        helper.write_text(": helper 1+ ;")
        self.source.write_text(": sample 99 ;")
        result = module.trace(self.source, "sample", gforth=GFORTH,
                              source_text="include ./helper.fs\n: sample 15 helper ;")
        self.successful(result, [16])
        self.assertEqual(self.source.read_text(), ": sample 99 ;")
        locations = {e["source"]["file"] for e in result["events"] if e["source"]}
        self.assertEqual(locations, {str(self.source), str(helper)})

    def test_snapshot_for_new_named_file_never_creates_source(self):
        result = module.trace(self.source, "sample", gforth=GFORTH,
                              source_text=": sample 42 ;")
        self.successful(result, [42])
        self.assertFalse(self.source.exists())

    def test_protocol_rejects_invalid_sequence_and_false_success(self):
        with self.assertRaises(ValueError):
            module.parse_trace("E 1 0 2 0\nX 0\n")
        with self.assertRaises(ValueError):
            module.parse_trace("X 0\n")


if __name__ == "__main__":
    unittest.main()
