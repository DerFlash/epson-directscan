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
    def test_single_page_marker_excludes_navigation_and_other_views(self):
        self.assertEqual(apple('return isSinglePageView({"In Computereinstellungen speichern"}, false)'), 'true')
        self.assertEqual(apple('return isSinglePageView({"In Computereinstellungen speichern"}, true)'), 'false')
        self.assertEqual(apple('return isSinglePageView({"Aktion wählen"}, false)'), 'false')

    def test_compiled_app_preserves_action_id_json_key(self):
        source = (ROOT / 'src/helper.applescript').read_text()
        command = ('script controller\n' + source + '\nend script\n'
                   + 'return controller\'s jsonText({op:"canDispatch", actionId:"job-1"})')
        result = subprocess.run(['osascript', '-e', command], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {'op': 'canDispatch', 'actionId': 'job-1'})

    def test_compiled_app_action_handshake_uses_real_runtime_without_ui_input(self):
        def literal(value):
            return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
        with tempfile.TemporaryDirectory(prefix='scansmart handshake ') as folder:
            source = (ROOT / 'src/helper.applescript').read_text()
            command = ('script controller\n' + source + '\non exerciseContract()\n'
                + 'set resourceFolder to (POSIX file ' + literal(str(ROOT / 'src')) + ') as alias\n'
                + 'set isolatedStorage to ' + literal(folder + '/settings') + '\n'
                + 'set targetFolder to ' + literal(folder) + '\n'
                + 'controller\'s resourceBridge(resourceFolder as text, {op:"startup", storageRoot:isolatedStorage})\n'
                + 'controller\'s resourceBridge(resourceFolder as text, {op:"setSettings", storageRoot:isolatedStorage, patch:{destination:targetFolder, enabled:true}})\n'
                + 'controller\'s resourceBridge(resourceFolder as text, {op:"tick", storageRoot:isolatedStorage, snapshot:{noJob:true, blocked:false}})\n'
                + 'set chooseFrame to {foreground:true, blocked:false, processId:17, windowTitle:"ScanSmart", captions:{"Aktion wählen"}, fields:{}, suffixLabels:{}, saveTargetCount:1, saveEnabled:true, noJob:false}\n'
                + 'set planned to controller\'s resourceBridge(resourceFolder as text, {op:"tick", storageRoot:isolatedStorage, snapshot:chooseFrame})\n'
                + 'set plannedAction to controller\'s getKey(planned, "action")\n'
                + 'set identifierValue to controller\'s getKey(plannedAction, "id") as text\n'
                + 'set permitted to controller\'s resourceBridge(resourceFolder as text, {op:"canDispatch", actionId:identifierValue, storageRoot:isolatedStorage, snapshot:chooseFrame})\n'
                + 'set acknowledged to controller\'s resourceBridge(resourceFolder as text, {op:"reportAction", actionId:identifierValue, storageRoot:isolatedStorage, success:true})\n'
                + 'return controller\'s jsonText({allowed:(controller\'s getKey(permitted, "allowed") as boolean), status:(controller\'s getKey(acknowledged, "status") as text)})\n'
                + 'end exerciseContract\nend script\nreturn controller\'s exerciseContract()')
            result = subprocess.run(['osascript', '-e', command], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {'allowed': True, 'status': 'awaiting_transition'})

    def test_page_navigation_fields_do_not_become_filename_prefixes(self):
        self.assertEqual(apple('return isExportField("AXComboBox")'), 'true')
        self.assertEqual(apple('return isExportField("AXTextField")'), 'false')

    def test_only_known_home_caption_is_idle(self):
        self.assertEqual(apple('return isIdleCaption({"Epson ScanSmart Klicken Sie zum Starten eines Scans auf [SCANNEN]."})'), 'true')
        self.assertEqual(apple('return isIdleCaption({"Scans prüfen", "In Computereinstellungen speichern"})'), 'false')
        self.assertEqual(apple('return isIdleCaption({"Unbekannte Ansicht"})'), 'false')

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
