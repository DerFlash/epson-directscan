ObjC.import('AppKit');
ObjC.import('ApplicationServices');

function parsePoint(args) {
    if (!args || args.length < 2 || args[0] === null || args[1] === null ||
        String(args[0]).trim() === '' || String(args[1]).trim() === '') {
        throw new Error('Ungültige Position');
    }
    var x = Number(args[0]), y = Number(args[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error('Ungültige Position');
    return {x: x, y: y};
}

function createClickEvents(point) {
    return [$.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp].map(function(kind) {
        var event = $.CGEventCreateMouseEvent(null, kind, point, $.kCGMouseButtonLeft);
        $.CGEventSetFlags(event, 0);
        $.CGEventSetIntegerValueField(event, $.kCGMouseEventClickState, 1);
        return event;
    });
}

function postVerifiedClick(args) {
    var point = parsePoint(args);
    var pid = Number(args[2]);
    if (args.length !== 3 || !Number.isInteger(pid) || pid <= 1) throw new Error('Ungültiger Prozess');
    var frontApp = $.NSWorkspace.sharedWorkspace.frontmostApplication;
    if (ObjC.unwrap(frontApp.bundleIdentifier) !== 'com.epson.scan.Epson-ScanSmart' ||
        Number(frontApp.processIdentifier) !== pid) throw new Error('ScanSmart nicht im Vordergrund');
    if (!$.AXIsProcessTrusted()) throw new Error('Bedienfreigabe fehlt');
    var events = createClickEvents(point);
    // JXA owns the bridged event references. Explicit CFRelease double-frees them.
    events.forEach(function(event) { $.CGEventPost($.kCGHIDEventTap, event); });
    return 'ok';
}
