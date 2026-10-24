const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function environment(bundle = 'com.epson.scan.Epson-ScanSmart', pid = 42, trusted = true) {
  const events = [];
  const dollar = {
    NSWorkspace: {sharedWorkspace: {frontmostApplication: {bundleIdentifier: bundle, processIdentifier: pid}}},
    AXIsProcessTrusted: () => trusted,
    kCGEventLeftMouseDown: 1, kCGEventLeftMouseUp: 2, kCGMouseButtonLeft: 0, kCGMouseEventClickState: 1, kCGHIDEventTap: 0,
    CGEventCreateMouseEvent: (_, type, point) => ({type, point}),
    CGEventSetFlags: (e, flags) => {e.flags = flags},
    CGEventSetIntegerValueField: (e, _, count) => {e.count = count},
    CGEventPost: (_, e) => events.push(e)
  };
  const ctx = vm.createContext({ObjC: {import() {}, unwrap: v => v}, $: dollar});
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../src/native-click.js'), 'utf8'), ctx);
  return {ctx, events};
}

test('native adapter refuses another app, changed PID and missing permission', () => {
  for (const args of [['other',42,true], ['com.epson.scan.Epson-ScanSmart',43,true], ['com.epson.scan.Epson-ScanSmart',42,false]]) {
    const {ctx, events} = environment(...args);
    assert.throws(() => ctx.postVerifiedClick([12,34,42]));
    assert.equal(events.length, 0);
  }
});

test('invalid native coordinates and process IDs never post', () => {
  for (const args of [[NaN,2,42], [1,Infinity,42], ['',2,42], [1,2,0], [1,2,42.5], [1,2,42,4]]) {
    const {ctx, events} = environment();
    assert.throws(() => ctx.postVerifiedClick(args));
    assert.equal(events.length, 0);
  }
});

test('verified adapter dispatches one unmodified click pair', () => {
  const {ctx, events} = environment();
  assert.equal(ctx.postVerifiedClick([12,34,42]), 'ok');
  assert.deepEqual(JSON.parse(JSON.stringify(events)), [
    {type:1, point:{x:12,y:34}, flags:0, count:1},
    {type:2, point:{x:12,y:34}, flags:0, count:1}
  ]);
});
