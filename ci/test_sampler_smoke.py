import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock,patch
import sampler_smoke as s

RAW=b'Process: Python [12]\nParent Process: Python [34]\nCall graph:\n    10 Thread_1\n    + 10 sleep (in libsystem_kernel.dylib) + 1\n    + 10 PyEval (in Python) + 2\n'
class Smoke(unittest.TestCase):
    def test_valid_stack(self):self.assertEqual(s.inspect_sample(RAW,12,34)['frame_lines'],2)
    def test_wrong_target(self):self.assertRaises(ValueError,s.inspect_sample,RAW,13,34)
    def test_wrong_parent(self):self.assertRaises(ValueError,s.inspect_sample,RAW,12,35)
    def test_empty(self):self.assertRaises(ValueError,s.inspect_sample,b'',12,34)
    def test_header_only(self):self.assertRaises(ValueError,s.inspect_sample,RAW.split(b'Call graph:')[0],12,34)
    def test_no_frames(self):self.assertRaises(ValueError,s.inspect_sample,RAW.split(b'    +')[0],12,34)
    def test_cleanup_denied_retains_uncertainty(self):
        child=Mock(pid=12,returncode=None);child.poll.return_value=None
        child.terminate.side_effect=PermissionError('denied');child.wait.side_effect=[subprocess.TimeoutExpired('x',.5),-9]
        child.kill.side_effect=PermissionError('denied')
        r=s.cleanup_target(child);self.assertIn('signal_error',r);self.assertIn('kill_error',r)
    def test_cli_good_bad_stuck(self):
        for mode in ('good','bad','stuck'):
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as tmp:
                path=Path(tmp)/'evidence'
                result=subprocess.run([sys.executable,'-B',s.__file__,str(path),'--offline',mode],capture_output=True,timeout=10)
                record=json.loads((path/'result.json').read_text())
                self.assertEqual(result.returncode,0 if mode=='good' else 1)
                self.assertEqual(record['passed'],mode=='good')
                self.assertTrue(record['target_cleanup']['reaped']);self.assertEqual(record['target_cleanup']['exit'],0)
                self.assertTrue((path/'target-stdout.raw').read_bytes().endswith(b'synthetic-target-terminated\n'))
                self.assertIsNotNone(record.get('observer_termination'))
                self.assertTrue((path/'observer-stderr.raw').exists())
if __name__=='__main__':unittest.main()
