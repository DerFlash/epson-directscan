"""Pure adapter tests. No accessibility permission or mouse input is used."""
import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def apple(probe):
    source = (ROOT / 'src/helper.applescript').read_text().split('-- Application lifecycle')[0]
    result = subprocess.run(['osascript', '-e', source + '\n' + probe], text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


class AdapterTests(unittest.TestCase):
    def test_only_exact_sharing_indicator_is_ignored(self):
        self.assertEqual(apple('return isSharingWindowData("Window", "AXDialog", {{"AXButton", "WindowSharingSessionButton"}})'), 'true')
        for data in [
            '"Fehler", "AXDialog", {{"AXButton", "WindowSharingSessionButton"}}',
            '"Window", "AXSystemDialog", {{"AXButton", "WindowSharingSessionButton"}}',
            '"Window", "AXDialog", {{"AXButton", "OK"}}',
            '"Window", "AXDialog", {{"AXButton", "WindowSharingSessionButton"}, {"AXStaticText", "Fehler"}}',
            '"Window", "AXDialog", {{"AXButton", "WindowSharingSessionButton"}, {"AXButton", "Speichern"}}',
        ]:
            self.assertEqual(apple('return isSharingWindowData(' + data + ')'), 'false')

    def test_null_and_missing_json_keys_are_missing_values(self):
        self.assertEqual(apple('set r to decodeJSON("{\\"errorCode\\":null}")\nreturn getKey(r, "errorCode") is missing value'), 'true')
        self.assertEqual(apple('set r to decodeJSON("{}")\nreturn getKey(r, "action") is missing value'), 'true')
        self.assertEqual(apple('set r to decodeJSON("{\\"status\\":\\"ready\\"}")\nreturn getKey(r, "status") as text'), 'ready')

    def test_resource_bridge_loads_real_runtime_and_private_settings(self):
        def literal(value):
            return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
        with tempfile.TemporaryDirectory(prefix='scansmart bridge ') as folder:
            source_path = literal(str(ROOT / 'src'))
            storage = literal(folder + '/private settings')
            value = json.loads(apple('set folderAlias to (POSIX file ' + source_path + ') as alias\n'
                + 'set r to resourceBridge(folderAlias as text, {op:"startup", storageRoot:' + storage + '})\nreturn jsonText(r)'))
            self.assertIs(value['ok'], True)
            self.assertEqual(value['phase'], 'arming')
            self.assertIs(value['settings']['enabled'], False)
            self.assertTrue((pathlib.Path(folder) / 'private settings/settings.json').is_file())

    def test_json_bridge_preserves_untrusted_folder_characters(self):
        value = json.loads(apple('return jsonText({op:"tick", snapshot:{foreground:true, fields:{"/Users/example/é \\\"$()\\\"", "Karte"}}})'))
        self.assertEqual(value['snapshot']['fields'], ['/Users/example/é "$()"', 'Karte'])
        self.assertIs(value['snapshot']['foreground'], True)

    def test_geometry_rejects_targets_outside_window(self):
        self.assertEqual(apple('return safePoint({200, 20}, {30, 10}, {0, 0}, {100, 100}) is missing value'), 'true')
        self.assertEqual(apple('return safePoint({20, 20}, {0, 10}, {0, 0}, {100, 100}) is missing value'), 'true')
        self.assertEqual(apple('return safePoint({-1, 20}, {30, 10}, {0, 0}, {100, 100}) is missing value'), 'true')

    def test_geometry_returns_center(self):
        self.assertEqual(apple('return safePoint({20, 20}, {30, 10}, {0, 0}, {100, 100})'), '35.0, 25.0')

    def test_capture_identity_detects_dialog_or_window_change(self):
        base = '{processIDValue:4, windowIdentity:1, rootIdentity:1, sheetNumber:0}'
        self.assertEqual(apple(f'return sameIdentity({base}, {base})'), 'true')
        changed = '{processIDValue:4, windowIdentity:1, rootIdentity:2, sheetNumber:1}'
        self.assertEqual(apple(f'return sameIdentity({base}, {changed})'), 'false')

    def test_suffix_recognition_excludes_free_text(self):
        self.assertEqual(apple('return isOutputSuffix("_0001.jpg")'), 'true')
        self.assertEqual(apple('return isOutputSuffix(".pdf")'), 'true')
        self.assertEqual(apple('return isOutputSuffix("Not a format: jpg")'), 'false')

    def test_bridge_passes_request_as_data_without_executing_text(self):
        self.assertEqual(apple('set r to evaluateBridge("function handleRequest(r) { return JSON.stringify({status:r.patch.destination}); }", {op:"setSettings", patch:{destination:"/tmp/é \\\"; throw Error(1); //"}})\nreturn getKey(r, "status") as text'), '/tmp/é "; throw Error(1); //')

    def test_native_invocation_passes_exact_integer_arguments(self):
        value = json.loads(apple('return runNativeScript("function postVerifiedClick(args) { return JSON.stringify(args); }", 123, 456, 789)'))
        self.assertEqual(value, [123, 456, 789])

    def test_status_explains_recovery_in_german(self):
        self.assertIn('vorhanden', apple('return friendlyStatus("target_exists")'))
        self.assertIn('Ordner', apple('return friendlyStatus("invalid_destination")'))
        self.assertIn('gespeichert', apple('return friendlyStatus("saved")'))


if __name__ == '__main__':
    unittest.main()
