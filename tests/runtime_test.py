import unittest, subprocess, tempfile, pathlib, json, os
ROOT = pathlib.Path(__file__).resolve().parents[1]

class Runtime(unittest.TestCase):
    def test_correct_destination_direct_save_survives_persistence_and_verifies(self):
        self.call('startup')
        self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
        idle = dict(foreground=True, blocked=False, processId=7, noJob=True)
        self.call('tick', snapshot=idle)
        view = dict(foreground=True, blocked=False, processId=7, noJob=False,
                    captions=['In Computereinstellungen speichern', '/ 1'],
                    fields=[self.dest, 'scan'], suffixLabels=['.jpg'],
                    saveTargetCount=1, saveEnabled=True)
        response = self.call('tick', snapshot=view)
        self.assertEqual(response['action']['type'], 'save')
        action_id = response['action']['id']
        self.assertTrue(self.call('canDispatch', snapshot=view, actionId=action_id)['allowed'])
        self.assertEqual(self.call('reportAction', actionId=action_id, success=True)['phase'], 'verifying')
        pathlib.Path(self.dest + '/scan.jpg').write_bytes((ROOT / 'tests/fixtures/tiny-white.jpg').read_bytes())
        self.assertEqual(self.call('tick', snapshot=idle)['phase'], 'verifying')
        self.assertEqual(self.call('tick', snapshot=idle)['status'], 'saved')

    def test_poll_interval_defaults_and_old_settings_migrate(self):
        self.assertEqual(self.call('startup')['settings']['pollIntervalMs'], 250)
        path = pathlib.Path(self.root + '/settings.json')
        old = json.loads(path.read_text())
        del old['pollIntervalMs']
        path.write_text(json.dumps(old))
        self.assertEqual(self.call('getSettings')['settings']['pollIntervalMs'], 250)
        self.assertEqual(json.loads(path.read_text())['pollIntervalMs'], 250)

    def test_interval_range_rejection_preserves_configuration(self):
        self.call('startup')
        self.assertEqual(self.call('setSettings', patch={'pollIntervalMs': 500})['settings']['pollIntervalMs'], 500)
        for value in [0, 99, 2001, 1.5, '250', True, None]:
            with self.subTest(value=value):
                self.assertEqual(self.call('setSettings', patch={'pollIntervalMs': value})['errorCode'], 'invalid_settings')
                self.assertEqual(self.call('getSettings')['settings']['pollIntervalMs'], 500)

    def test_interval_change_preserves_pending_action_and_acknowledgment(self):
        self.call('startup')
        self.call('setSettings', patch={'destination': self.dest, 'enabled': True})
        self.call('tick', snapshot={'noJob': True, 'blocked': False})
        choose = dict(foreground=True, blocked=False, processId=7, captions=['Aktion wählen'], saveTargetCount=1, saveEnabled=True, noJob=False)
        action = self.call('tick', snapshot=choose)['action']
        changed = self.call('setSettings', patch={'pollIntervalMs': 100})
        self.assertEqual(changed['phase'], 'opening')
        self.assertEqual(json.loads(pathlib.Path(self.root + '/state.json').read_text())['pending']['action']['id'], action['id'])
        self.assertEqual(self.call('reportAction', actionId=action['id'], success=True)['status'], 'awaiting_transition')

    def test_timing_samples_are_bounded_sanitized_and_private(self):
        self.call('startup')
        sample = dict(settingsMs=1, captureMs=20, policyMs=2, actionMs=30, totalMs=60, privatePath='/private/scan.jpg')
        response = self.call('recordTiming', sample=sample, actionType='save', privateTitle='secret')
        self.assertTrue(response['ok'])
        path = pathlib.Path(self.root + '/timings.json')
        first = json.loads(path.read_text())[0]
        self.assertEqual(first['captureMs'], 20)
        self.assertEqual(first['actionType'], 'save')
        self.assertEqual(first['intervalMs'], 250)
        self.assertGreater(first['atMs'], 0)
        self.assertNotIn('private', path.read_text())
        self.assertNotIn('secret', path.read_text())
        path.write_text(json.dumps([dict(first, privateTitle='secret')] * 150))
        self.call('recordTiming', sample=sample, actionType='openSave')
        self.assertEqual(len(self.call('getTimings')['timings']), 128)
        self.assertNotIn('secret', path.read_text())
        self.assertEqual(path.stat().st_mode & 511, 384)

    def test_invalid_or_unwritable_timing_never_resets_scan_state(self):
        self.call('startup')
        before = pathlib.Path(self.root + '/state.json').read_text()
        sample = dict(settingsMs=1, captureMs=2, policyMs=3, actionMs=4, totalMs=10)
        self.assertEqual(self.call('recordTiming', sample=dict(sample, captureMs=-1), actionType='save')['timingError'], 'invalid_settings')
        os.mkdir(self.root + '/timings.json')
        self.assertEqual(self.call('recordTiming', sample=sample, actionType='save')['timingError'], 'storage_error')
        self.assertEqual(pathlib.Path(self.root + '/state.json').read_text(), before)
        self.assertEqual(self.call('getSettings')['phase'], 'arming')

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
