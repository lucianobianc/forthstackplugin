import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('label_trace', ROOT / 'prototype/trace.py')
tracer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tracer)


class LabelTests(unittest.TestCase):
    def run_source(self, source, entry=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'labels.fs'
            path.write_text(source)
            digest = hashlib.sha256(path.read_bytes()).digest()
            result = tracer.trace(path, entry, gforth=os.environ.get('GFORTH', 'gforth'))
            self.assertEqual(hashlib.sha256(path.read_bytes()).digest(), digest)
            return result

    def successful(self, source, entry=None):
        result = self.run_source(source, entry)
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['format_version'], 2)
        for event in result['events']:
            self.assertEqual([e['value'] for e in event['elements']], event['stack'])
            self.assertEqual(len({e['id'] for e in event['elements']}), len(event['stack']))
        return result

    def last(self, result):
        return result['events'][-1]['elements']

    def test_user_example_including_literal_increment(self):
        for body in ('1+', '1 +'):
            with self.subTest(body=body):
                result = self.successful(f': birthday {body} ;\n: can-drive 18 >= ;\n'
                                         '17 ( LABEL: age )\ndup can-drive drop\ndup birthday\ncan-drive')
                final = self.last(result)
                self.assertEqual([(e['value'], e['label']) for e in final], [(17, 'age'), (-1, None)])
                calls = [e for e in result['events'] if e['source'] and
                         e['source']['token'] == 'birthday' and e['phase'] == 'after']
                elements = calls[0]['elements']
                self.assertEqual([(e['value'], e['label']) for e in elements], [(17, 'age'), (18, 'age')])
                self.assertNotEqual(elements[0]['id'], elements[1]['id'])
                self.assertEqual(elements[1]['origin'], elements[0]['id'])

    def test_stack_permutations_preserve_identities_and_duplicate_origins(self):
        prefix = '10 ( LABEL: a ) 20 ( LABEL: b ) 30 ( LABEL: c ) '
        expected = {
            'dup': ['a', 'b', 'c', 'c'], 'drop': ['a', 'b'],
            'swap': ['a', 'c', 'b'], 'over': ['a', 'b', 'c', 'b'],
            'rot': ['b', 'c', 'a'], 'nip': ['a', 'c'], 'tuck': ['a', 'c', 'b', 'c'],
        }
        for op, labels in expected.items():
            with self.subTest(op=op):
                result = self.successful(prefix + op)
                elements = self.last(result)
                self.assertEqual([e['label'] for e in elements], labels)
                before = [e for e in result['events'] if e['phase'] == 'before'][-1]['elements']
                old = {e['label']: e['id'] for e in before}
                if op in ('dup', 'over', 'tuck'):
                    self.assertEqual(elements[-1]['origin'], old[labels[-1]])
                    self.assertNotEqual(elements[-1]['id'], old[labels[-1]])
                else:
                    self.assertTrue(all(e['id'] == old[e['label']] for e in elements))

    def test_equal_values_are_not_used_to_match_identity(self):
        result = self.successful('17 ( LABEL: a ) 17 ( LABEL: b ) swap drop')
        self.assertEqual(self.last(result)[0]['label'], 'b')
        swap = [e for e in result['events'] if e['phase'] == 'after' and e['source']['token'] == 'swap'][0]
        self.assertEqual([e['label'] for e in swap['elements']], ['b', 'a'])

    def test_increment_decrement_preserve_id_and_earlier_snapshots(self):
        result = self.successful('17 ( LABEL: age ) 1+ 1- 1 -')
        annotated = next(e for e in result['events'] if e['phase'] == 'label')['elements'][-1]
        final = self.last(result)[0]
        self.assertEqual((annotated['value'], annotated['label']), (17, 'age'))
        self.assertEqual((final['value'], final['label']), (16, 'age'))
        self.assertEqual(annotated['id'], final['id'])

    def test_comparisons_and_general_arithmetic_do_not_inherit_labels(self):
        for op in ('>=', '=', '<', '>', '+', '-', '*'):
            with self.subTest(op=op):
                result = self.successful('5 ( LABEL: keep ) 17 ( LABEL: age ) 18 ' + op)
                self.assertEqual([e['label'] for e in self.last(result)], ['keep', None])
        result = self.successful('17 ( LABEL: age ) 0=')
        self.assertIsNone(self.last(result)[0]['label'])

    def test_compiled_annotation_runs_on_every_call(self):
        result = self.successful(': make 17 ( LABEL: age ) ; make make')
        self.assertEqual([e['label'] for e in self.last(result)], ['age', 'age'])
        self.assertNotEqual(*[e['id'] for e in self.last(result)])
        source = [e['source'] for e in result['events'] if e['phase'] == 'label']
        self.assertTrue(all(s['word'] == 'make' and s['token'] == '(' for s in source))

    def test_loops_and_recursion_do_not_reuse_fresh_instance_ids(self):
        result = self.successful(': sample 3 0 do 17 ( LABEL: age ) loop ;', 'sample')
        self.assertEqual([e['label'] for e in self.last(result)], ['age'] * 3)
        result = self.successful(': count dup 0= if exit then 1- recurse ;\n3 ( LABEL: n ) count')
        # An opaque branch can invalidate identities; it must never invent labels.
        self.assertEqual(result['events'][-1]['stack'], [0])

    def test_shadowed_primitive_uses_its_body_not_its_name(self):
        result = self.successful(': dup drop 99 ; 17 ( LABEL: age ) dup')
        self.assertEqual([(e['value'], e['label']) for e in self.last(result)], [(99, None)])
        call = [s for s in result['sites'].values() if s['token'] == 'dup'][0]
        self.assertEqual(call['operation'], 'call')

    def test_opaque_macro_cannot_silently_swap_equal_value_labels(self):
        result = self.successful(': hidden-swap postpone swap ; immediate\n'
                                 ': sample hidden-swap ;\n'
                                 '17 ( LABEL: a ) 17 ( LABEL: b ) sample')
        self.assertEqual([e['label'] for e in self.last(result)], [None, None])
        self.assertTrue(any(e['phase'] == 'opaque' for e in result['events']))

    def test_unknown_precompiled_word_is_a_conservative_barrier(self):
        result = self.successful('17 ( LABEL: age ) noop')
        self.assertIsNone(self.last(result)[0]['label'])

    def test_relabeling_a_copy_does_not_change_the_original(self):
        result = self.successful('17 ( LABEL: age ) dup ( LABEL: copy )')
        self.assertEqual([e['label'] for e in self.last(result)], ['age', 'copy'])

    def test_comments_and_strings_are_not_scanned_as_annotations(self):
        result = self.run_source('\\ ( LABEL: ignored )\n17 s" ( LABEL: ignored )" type')
        self.assertTrue(result['complete'], result)
        self.assertEqual(result['format_version'], 1)
        result = self.run_source('17 ( ordinary LABEL: ignored )')
        self.assertEqual(result['format_version'], 1)

    def test_invalid_or_empty_labels_and_empty_stack_are_reported(self):
        for label in ('', 'two words', '123', 'a' * 65):
            with self.subTest(label=label):
                result = self.run_source(f'17 ( LABEL: {label} )')
                self.assertFalse(result['complete'])
                self.assertIn('Invalid LABEL', result['diagnostic'])
        result = self.run_source('( LABEL: age )')
        self.assertEqual(result['status'], 'label_error')
        self.assertIn('empty stack', result['diagnostic'])

    def test_gforth_behavior_and_output_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'sample.fs'
            source = ': birthday 1+ ; 17 ( LABEL: age ) birthday .'
            path.write_text(source)
            plain = subprocess.run([os.environ.get('GFORTH', 'gforth'), str(path), '-e', 'bye'],
                                   capture_output=True, text=True, check=True)
            traced = self.successful(source)
            self.assertEqual(plain.stdout, traced['stdout'])


if __name__ == '__main__':
    unittest.main()
