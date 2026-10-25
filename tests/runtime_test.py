import unittest, subprocess, tempfile, pathlib, json, os
ROOT = pathlib.Path(__file__).resolve().parents[1]

class Runtime(unittest.TestCase):
    def test_observation_retry_status_and_error_number_persist_safely(self):
        self.call('startup')
        self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
        self.call('tick', snapshot={'noJob': True, 'blocked': False})
        response = self.call('observationError', errorNumber=-1719)
        self.assertEqual(response['status'], 'waiting_for_view')
        self.assertEqual(self.call('getSettings')['errorNumber'], -1719)
        self.assertEqual(self.call('tick', snapshot={'noJob': True, 'blocked': False})['status'], 'ready')
        response = self.call('observationError', errorNumber=-1700)
        self.assertEqual(response['errorCode'], 'adapter_error')
        self.assertEqual(self.call('getSettings')['errorNumber'], -1700)


    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name + '/storage'
        self.dest = self.tmp.name + '/ä "folder'
        os.mkdir(self.dest)

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, op, **kw):
        now = kw.pop('now', 10)
        req = dict(op=op, storageRoot=self.root, now=now, **kw)
        source = (ROOT / 'src/core.js').read_text() + '\n' + (ROOT / 'src/runtime.js').read_text() + '\nhandleRequest(' + json.dumps(req) + ');'
        x = subprocess.run(['osascript', '-l', 'JavaScript', '-e', source], capture_output=True, text=True)
        self.assertEqual(x.returncode, 0, x.stderr)
        return json.loads(x.stdout)

    def test_roundtrip_permissions_restart(self):
        self.assertFalse(self.call('startup')['settings']['enabled'])
        x = self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
        self.assertTrue(x['ok'])
        self.assertEqual(x['settings']['destination'], self.dest)
        self.assertEqual(self.call('startup')['phase'], 'arming')
        for name in ['settings.json', 'state.json']:
            self.assertEqual(os.stat(self.root + '/' + name).st_mode & 511, 384)
        self.assertEqual(os.stat(self.root).st_mode & 511, 448)

    def test_invalid_destination_and_json(self):
        self.assertFalse(self.call('setSettings', patch={'destination': 'relative'})['ok'])
        self.assertFalse(self.call('setSettings', patch={'enabled': 'yes'})['ok'])

    def test_corrupt_state_visible(self):
        self.call('startup')
        pathlib.Path(self.root + '/state.json').write_text('{')
        self.assertEqual(self.call('tick')['errorCode'], 'storage_error')

    def test_symlink_storage_and_destination(self):
        os.symlink(self.dest, self.root)
        self.assertFalse(self.call('startup')['ok'])
        os.unlink(self.root)
        link = self.tmp.name + '/link'
        os.symlink(self.dest, link)
        self.assertFalse(self.call('setSettings', patch={'destination': link})['ok'])

    def test_reservation_persisted_and_file_verification(self):
        self.call('startup')
        self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
        idle = dict(foreground=True, blocked=False, processId=7, windowTitle='ScanSmart', captions=[], fields=[], suffixLabels=[], saveTargetCount=0, saveEnabled=False, noJob=True)
        self.call('tick', snapshot=idle)
        save = dict(idle, captions=['In Computereinstellungen speichern', '/ 1'], fields=['/old', 'scan'], suffixLabels=['.jpg'], saveTargetCount=1, saveEnabled=True, noJob=False)
        x = self.call('tick', snapshot=save)
        action = x['action']
        self.assertEqual(action['type'], 'setDestination')
        self.assertEqual(json.loads(pathlib.Path(self.root + '/state.json').read_text())['pending']['action']['id'], action['id'])
        self.call('reportAction', actionId=action['id'], success=True)
        save['fields'] = [self.dest, 'scan']
        x = self.call('tick', snapshot=save)
        self.assertEqual(x['action']['type'], 'save')
        self.call('reportAction', actionId=x['action']['id'], success=True)
        pathlib.Path(self.dest + '/scan.jpg').write_bytes((ROOT / 'tests/fixtures/tiny-white.jpg').read_bytes())
        self.assertEqual(self.call('tick', snapshot=idle)['phase'], 'verifying')
        self.assertEqual(self.call('tick', snapshot=idle)['phase'], 'ready')

    def test_normalized_destination(self):
        self.call('startup')
        x = self.call('setSettings', patch={'destination': self.dest + '/./', 'enabled': True})
        self.assertEqual(x['settings']['destination'], self.dest)

    def test_missing_destination_pause_persists_after_return(self):
        self.call('startup')
        self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
        os.rmdir(self.dest)
        self.assertEqual(self.call('getSettings')['errorCode'], 'invalid_destination')
        os.mkdir(self.dest)
        self.assertEqual(self.call('getSettings')['phase'], 'paused')
        self.assertEqual(self.call('tick', snapshot={'noJob': True, 'blocked': False})['phase'], 'paused')

    def test_corrupt_state_is_replaced_by_persistent_pause(self):
        self.call('startup')
        pathlib.Path(self.root + '/state.json').write_text('{')
        self.assertEqual(self.call('getSettings')['errorCode'], 'storage_error')
        self.assertEqual(json.loads(pathlib.Path(self.root + '/state.json').read_text())['phase'], 'paused')

    def test_invalid_plan_and_pending_fail_closed(self):
        self.call('startup')
        baseline = json.loads(pathlib.Path(self.root + '/state.json').read_text())
        for mutation in [{'phase': 'verifying', 'since': 10, 'plan': {'paths': ['/private/other']}}, {'pending': {'action': {'type': 'save'}}}]:
            state = dict(baseline, **mutation)
            pathlib.Path(self.root + '/state.json').write_text(json.dumps(state))
            self.assertEqual(self.call('getSettings')['errorCode'], 'storage_error')

    def test_logs_discard_unknown_keys_private_values(self):
        self.call('startup')
        pathlib.Path(self.root + '/events.json').write_text(json.dumps([{'code': '/private/file', 'phase': 'ready', 'secret': 'sensitive'}, {'code': 'ready', 'phase': 'ready', 'secret': 'sensitive'}]))
        self.call('reset')
        text = pathlib.Path(self.root + '/events.json').read_text()
        self.assertNotIn('private', text)
        self.assertNotIn('sensitive', text)

    def test_invalid_jpegs_remain_unconfirmed_then_timeout_without_retry(self):
        jpeg = (ROOT / 'tests/fixtures/tiny-white.jpg').read_bytes()
        cases = {'soi_only': b'\xff\xd8', 'truncated_real': jpeg[:len(jpeg) // 2], 'marker_wrapped_garbage': b'\xff\xd8garbage\xff\xd9', 'non_jpeg': b'not an image'}
        for name, data in cases.items():
            with self.subTest(name=name):
                pathlib.Path(self.dest + '/scan.jpg').unlink(missing_ok=True)
                self.call('startup')
                self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
                idle = dict(foreground=True, blocked=False, processId=7, windowTitle='ScanSmart', captions=[], fields=[], suffixLabels=[], saveTargetCount=0, saveEnabled=False, noJob=True)
                self.call('tick', snapshot=idle)
                save = dict(idle, captions=['In Computereinstellungen speichern', '/ 1'], fields=['/old', 'scan'], suffixLabels=['.jpg'], saveTargetCount=1, saveEnabled=True, noJob=False)
                x = self.call('tick', snapshot=save)
                self.call('reportAction', actionId=x['action']['id'], success=True)
                save['fields'] = [self.dest, 'scan']
                x = self.call('tick', snapshot=save)
                self.call('reportAction', actionId=x['action']['id'], success=True)
                output = pathlib.Path(self.dest + '/scan.jpg')
                output.write_bytes(data)
                for _ in range(2):
                    response = self.call('tick', snapshot=idle)
                    self.assertEqual(response['phase'], 'verifying')
                    self.assertNotIn('action', response)
                response = self.call('tick', snapshot=idle, now=131)
                self.assertEqual(response['errorCode'], 'export_timeout')
                self.assertNotIn('action', response)
                self.assertNotIn('action', self.call('tick', snapshot=save, now=132))
                output.unlink()
if __name__ == '__main__':
    unittest.main()
