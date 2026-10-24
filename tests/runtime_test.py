import unittest, subprocess, tempfile, pathlib, json, os
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Runtime(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=self.tmp.name+'/storage';self.dest=self.tmp.name+'/ä "folder';os.mkdir(self.dest)
 def tearDown(self): self.tmp.cleanup()
 def call(self,op,**kw):
  req=dict(op=op,storageRoot=self.root,now=10,**kw)
  source=(ROOT/'src/core.js').read_text()+'\n'+(ROOT/'src/runtime.js').read_text()+'\nhandleRequest('+json.dumps(req)+');'
  x=subprocess.run(['osascript','-l','JavaScript','-e',source],capture_output=True,text=True)
  self.assertEqual(x.returncode,0,x.stderr);return json.loads(x.stdout)
 def test_roundtrip_permissions_restart(self):
  self.assertFalse(self.call('startup')['settings']['enabled'])
  x=self.call('setSettings',patch={'destination':self.dest,'enabled':True});self.assertTrue(x['ok']);self.assertEqual(x['settings']['destination'],self.dest)
  self.assertEqual(self.call('startup')['phase'],'arming')
  for name in ['settings.json','state.json']:
   self.assertEqual(os.stat(self.root+'/'+name).st_mode&0o777,0o600)
  self.assertEqual(os.stat(self.root).st_mode&0o777,0o700)
 def test_invalid_destination_and_json(self):
  self.assertFalse(self.call('setSettings',patch={'destination':'relative'})['ok'])
  self.assertFalse(self.call('setSettings',patch={'enabled':'yes'})['ok'])
 def test_corrupt_state_visible(self):
  self.call('startup');pathlib.Path(self.root+'/state.json').write_text('{');self.assertEqual(self.call('tick')['errorCode'],'storage_error')
 def test_symlink_storage_and_destination(self):
  os.symlink(self.dest,self.root);self.assertFalse(self.call('startup')['ok']);os.unlink(self.root)
  link=self.tmp.name+'/link';os.symlink(self.dest,link);self.assertFalse(self.call('setSettings',patch={'destination':link})['ok'])
 def test_reservation_persisted_and_file_verification(self):
  self.call('startup');self.call('setSettings',patch={'destination':self.dest,'enabled':True})
  idle=dict(foreground=True,blocked=False,processId=7,windowTitle='ScanSmart',captions=[],fields=[],suffixLabels=[],saveTargetCount=0,saveEnabled=False,noJob=True)
  self.call('tick',snapshot=idle)
  save=dict(idle,captions=['In Computereinstellungen speichern','/ 1'],fields=['/old','scan'],suffixLabels=['.jpg'],saveTargetCount=1,saveEnabled=True,noJob=False)
  x=self.call('tick',snapshot=save);action=x['action'];self.assertEqual(action['type'],'setDestination')
  self.assertEqual(json.loads(pathlib.Path(self.root+'/state.json').read_text())['pending']['action']['id'],action['id'])
  self.call('reportAction',actionId=action['id'],success=True);save['fields']=[self.dest,'scan']
  x=self.call('tick',snapshot=save);self.assertEqual(x['action']['type'],'save')
  self.call('reportAction',actionId=x['action']['id'],success=True)
  pathlib.Path(self.dest+'/scan.jpg').write_bytes(b'\xff\xd8abc')
  self.assertEqual(self.call('tick',snapshot=idle)['phase'],'verifying')
  self.assertEqual(self.call('tick',snapshot=idle)['phase'],'ready')
 def test_normalized_destination(self):
  self.call('startup');x=self.call('setSettings',patch={'destination':self.dest+'/./','enabled':True});self.assertEqual(x['settings']['destination'],self.dest)
 def test_missing_destination_pause_persists_after_return(self):
  self.call('startup');self.call('setSettings',patch={'destination':self.dest,'enabled':True});os.rmdir(self.dest)
  self.assertEqual(self.call('getSettings')['errorCode'],'invalid_destination');os.mkdir(self.dest)
  self.assertEqual(self.call('getSettings')['phase'],'paused');self.assertEqual(self.call('tick',snapshot={'noJob':True,'blocked':False})['phase'],'paused')
 def test_corrupt_state_is_replaced_by_persistent_pause(self):
  self.call('startup');pathlib.Path(self.root+'/state.json').write_text('{')
  self.assertEqual(self.call('getSettings')['errorCode'],'storage_error');self.assertEqual(json.loads(pathlib.Path(self.root+'/state.json').read_text())['phase'],'paused')
 def test_invalid_plan_and_pending_fail_closed(self):
  for state in [{'phase':'verifying','plan':{'paths':['/private/other']}}, {'phase':'ready','pending':{'action':{'type':'save'}}}]:
   self.call('startup');pathlib.Path(self.root+'/state.json').write_text(json.dumps(state));self.assertEqual(self.call('getSettings')['errorCode'],'storage_error')
 def test_logs_discard_unknown_keys_private_values(self):
  self.call('startup');pathlib.Path(self.root+'/events.json').write_text(json.dumps([{'code':'/private/file','phase':'ready','secret':'sensitive'},{'code':'ready','phase':'ready','secret':'sensitive'}]))
  self.call('reset');text=pathlib.Path(self.root+'/events.json').read_text();self.assertNotIn('private',text);self.assertNotIn('sensitive',text)
if __name__=='__main__': unittest.main()
