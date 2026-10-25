/* Native Foundation storage and ImageIO verification; never sends UI input. */
ObjC.import('Foundation');
ObjC.import('ImageIO');
ObjC.import('CoreGraphics');
function handleRequest(request) {
    var settings={destination:null,enabled:false,dryRun:false}, state=AutoSaveCore.initialState(), storageReady=false;
    try {
        var r=typeof request==='string'?JSON.parse(request):request;
        var fm=$.NSFileManager.defaultManager;
        var root=r.storageRoot || ObjC.unwrap($.NSHomeDirectory())+'/Library/Application Support/ScanSmart AutoSave';
        if(typeof root!=='string' || root[0]!=='/' || root.indexOf('\x00')>=0)throw Error('storage_error');
        function attrs(path){var a=fm.attributesOfItemAtPathError($(path),null);return a?ObjC.deepUnwrap(a):null;}
        function directory(path){var a=attrs(path);return a && a.NSFileType==='NSFileTypeDirectory';}
        function chmod(path,mode){if(!fm.setAttributesOfItemAtPathError($({NSFilePosixPermissions:mode}),$(path),null))throw Error('storage_error');}
        if(!attrs(root)) {if(!fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(root),true,$({NSFilePosixPermissions:448}),null))throw Error('storage_error');}
        if(!directory(root))throw Error('storage_error');chmod(root,448);storageReady=true;
        function read(name,fallback){var path=root+'/'+name,a=attrs(path);if(!a)return fallback;if(a.NSFileType!=='NSFileTypeRegular')throw Error('storage_error');var text=$.NSString.stringWithContentsOfFileEncodingError($(path),$.NSUTF8StringEncoding,null);if(!text)throw Error('storage_error');chmod(path,384);return JSON.parse(ObjC.unwrap(text));}
        function write(name,value){var path=root+'/'+name;if(attrs(path)&&attrs(path).NSFileType!=='NSFileTypeRegular')throw Error('storage_error');if(attrs(path)){var current=$.NSString.stringWithContentsOfFileEncodingError($(path),$.NSUTF8StringEncoding,null);if(current && ObjC.unwrap(current)===JSON.stringify(value)){chmod(path,384);return;}}var temp=root+'/.write-'+ObjC.unwrap($.NSUUID.UUID.UUIDString);var data=$(JSON.stringify(value)).dataUsingEncoding($.NSUTF8StringEncoding);try{if(!data.writeToFileOptionsError($(temp),$.NSDataWritingAtomic,null))throw Error('storage_error');chmod(temp,384);if(!fm.replaceItemAtURLWithItemAtURLBackupItemNameOptionsResultingItemURLError){throw Error('storage_error');}if(attrs(path)){if(!fm.replaceItemAtURLWithItemAtURLBackupItemNameOptionsResultingItemURLError($.NSURL.fileURLWithPath($(path)),$.NSURL.fileURLWithPath($(temp)),$(),0,null,null))throw Error('storage_error');}else if(!fm.moveItemAtPathToPathError($(temp),$(path),null))throw Error('storage_error');chmod(path,384);}finally{fm.removeItemAtPathError($(temp),null);}}
        var phases=['arming','ready','opening','setting_destination','verifying','paused'];
        var codes=['waiting_for_idle','waiting_for_view','ready','saved','disabled','opening_save','setting_destination','awaiting_transition','saving','verifying_files','dry_run_open_save','dry_run_set_destination','invalid_metadata','counter_overflow','target_exists','destination_readback','transition_timeout','export_timeout','dispatch_failed','destination_rejected','ui_changed','permission_denied','adapter_error','bridge_error','unsupported_view','invalid_destination','storage_error'];
        function cleanLogs(){var lines;try{lines=read('events.json',[]);}catch(e){lines=[];}if(!Array.isArray(lines))lines=[];return lines.filter(function(x){return x&&codes.indexOf(x.code)>=0&&phases.indexOf(x.phase)>=0;}).slice(-127).map(function(x){return {code:x.code,phase:x.phase};});}
        var logs=cleanLogs();write('events.json',logs);
        settings=read('settings.json',settings);state=read('state.json',state);
        if(!settings || typeof settings.enabled!=='boolean' || typeof settings.dryRun!=='boolean' || !(settings.destination===null || typeof settings.destination==='string'))throw Error('storage_error');
        if(!state || ['arming','ready','opening','setting_destination','verifying','paused'].indexOf(state.phase)<0)throw Error('storage_error');
        function validPlan(p){try{if(!p || !Array.isArray(p.paths))return false;var expected=AutoSaveCore.metadata({captions:['/ '+p.count],fields:[p.folder,p.prefix],suffixLabels:[p.suffix]},settings.destination);return JSON.stringify(expected)===JSON.stringify(p);}catch(e){return false;}}
        if(!Number.isSafeInteger(state.sequence)||state.sequence<0 || codes.indexOf(state.status)<0 || !(state.errorCode===null||codes.indexOf(state.errorCode)>=0))throw Error('storage_error');
        if(state.lastErrorNumber!==undefined&&!Number.isInteger(state.lastErrorNumber))throw Error('storage_error');
        if(state.readFailureSince!==undefined&&(!Number.isFinite(state.readFailureSince)||state.readFailureSince<0))throw Error('storage_error');
        if(['opening','setting_destination','verifying'].indexOf(state.phase)>=0 && (!Number.isFinite(state.since)||state.since<0))throw Error('storage_error');
        if((state.phase==='verifying'||state.phase==='setting_destination')&&!validPlan(state.plan))throw Error('storage_error');
        if(state.pending){var p=state.pending;if(!p.action||typeof p.action.id!=='string'||p.action.id.length>100||['openSave','setDestination','save'].indexOf(p.action.type)<0||!Number.isInteger(p.pid)||p.pid<1||(['opening','setting_destination'].indexOf(state.phase)<0)||(p.action.type!=='openSave'&&!validPlan(p.plan)))throw Error('storage_error');}
        function normalized(d){if(typeof d!=='string'||d[0]!=='/'||d.indexOf('\x00')>=0)throw Error('invalid_destination');return ObjC.unwrap($(d).stringByStandardizingPath).replace(/\/$/,'')||'/';}
        function validDestination(d){return typeof d==='string' && d[0]==='/' && d.indexOf('\x00')<0 && directory(d) && fm.isWritableFileAtPath($(d));}
        var op=r.op||r.type;
        if(['startup','getSettings','setSettings','reset','tick','canDispatch','reportAction','pause','observationError'].indexOf(op)<0)throw Error('unknown_request');
        if(op==='setSettings'){
            var patch=r.patch||{}, next=JSON.parse(JSON.stringify(settings));
            Object.keys(patch).forEach(function(k){if(['destination','enabled','dryRun'].indexOf(k)<0)throw Error('invalid_settings');if(k==='destination'){if(patch[k]!==null&&!validDestination(patch[k]))throw Error('invalid_destination');}else if(typeof patch[k]!=='boolean')throw Error('invalid_settings');next[k]=k==='destination'&&patch[k]!==null?normalized(patch[k]):patch[k];});
            if(next.enabled&&!validDestination(next.destination))throw Error('invalid_destination');
            if(JSON.stringify(next)!==JSON.stringify(settings)){state=AutoSaveCore.initialState();write('state.json',state);settings=next;write('settings.json',settings);}
        }
        if(settings.enabled&&!validDestination(settings.destination))throw Error('invalid_destination');
        function inspect(path) {
            var attributes = attrs(path);
            if (!attributes) return {exists:false};
            if (attributes.NSFileType !== 'NSFileTypeRegular') {
                return {exists:true, regular:false, jpeg:false, size:0};
            }
            var size = Number(attributes.NSFileSize);
            var jpeg = false;
            var handle = $.NSFileHandle.fileHandleForReadingAtPath($(path));
            if (handle && size >= 4) {
                try {
                    var start = handle.readDataOfLength(2);
                    handle.seekToFileOffset(size - 2);
                    var end = handle.readDataOfLength(2);
                    var hasMarkers = ObjC.unwrap(start.base64EncodedStringWithOptions(0)) === '/9g=' &&
                        ObjC.unwrap(end.base64EncodedStringWithOptions(0)) === '/9k=';
                    if (hasMarkers) {
                        var source = $.CGImageSourceCreateWithURL($.NSURL.fileURLWithPath($(path)), $());
                        if (source && Number($.CGImageSourceGetCount(source)) === 1 &&
                            ObjC.unwrap(ObjC.castRefToObject($.CGImageSourceGetType(source))) === 'public.jpeg' &&
                            Number($.CGImageSourceGetStatus(source)) === 0 &&
                            Number($.CGImageSourceGetStatusAtIndex(source, 0)) === 0) {
                            var options = {};
                            options[ObjC.unwrap(ObjC.castRefToObject($.kCGImageSourceShouldCacheImmediately))] = true;
                            var image = $.CGImageSourceCreateImageAtIndex(source, 0, $(options));
                            jpeg = !!image && Number($.CGImageGetWidth(image)) > 0 &&
                                Number($.CGImageGetHeight(image)) > 0 &&
                                Number($.CGImageSourceGetStatus(source)) === 0 &&
                                Number($.CGImageSourceGetStatusAtIndex(source, 0)) === 0;
                        }
                        // JXA owns bridged source/image references; do not CFRelease them.
                    }
                } catch (decodeError) {
                    jpeg = false;
                } finally {
                    handle.closeFile;
                }
            } else if (handle) {
                handle.closeFile;
            }
            return {exists:true, regular:true, jpeg:jpeg, size:size};
        }
        var result=AutoSaveCore.step(state,settings,r,{now:r.now===undefined?Number($.NSProcessInfo.processInfo.systemUptime):Number(r.now),inspect:inspect});
        write('settings.json',settings);write('state.json',result.state);
        if(state.status!==result.state.status || state.errorCode!==result.state.errorCode){
            var lines=logs;lines.push({code:result.state.status,phase:result.state.phase});if(lines.length>128)lines=lines.slice(-128);write('events.json',lines);
        }
        return JSON.stringify(result.response);
    } catch(e) {
        var code=/^(invalid_settings|invalid_destination|unknown_request)$/.test(e.message)?e.message:'storage_error';
        if(storageReady && (code==='storage_error'||code==='invalid_destination')){try{var paused=AutoSaveCore.initialState();paused.phase='paused';paused.status=code;paused.errorCode=code;write('state.json',paused);}catch(ignore){}}
        return JSON.stringify({ok:false,settings:settings,phase:'paused',status:code,errorCode:code});
    }
}
