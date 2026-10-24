/* Pure state transitions. No UI or filesystem access. */
var AutoSaveCore = (function () {
    function initialState() { return {phase:'arming',status:'waiting_for_idle',errorCode:null,sequence:0}; }
    function view(s) {
        if (!s || s.blocked) return 'blocked';
        if (Array.isArray(s.captions) && s.captions.indexOf('In Computereinstellungen speichern')>=0 && s.captions.indexOf('Aktion wählen')>=0) return 'blocked';
        if (s.noJob === true) return 'idle';
        if (!Number.isInteger(s.processId) || s.processId < 1) return 'blocked';
        if (!Array.isArray(s.captions)) return 'blocked';
        if (s.captions.indexOf('In Computereinstellungen speichern') >= 0) return 'save';
        if (s.captions.indexOf('Aktion wählen') >= 0) return 'choose';
        return 'blocked';
    }
    function metadata(s,destination) {
        var suffix=s.suffixLabels||[], fields=s.fields||[], counts=[];
        (s.captions||[]).forEach(function(c){var m=String(c).match(/\/\s*(\d+)\s*$/);if(m && counts.indexOf(Number(m[1]))<0)counts.push(Number(m[1]));});
        if(suffix.length!==1 || counts.length!==1 || counts[0]<1 || counts[0]>10000) throw Error('invalid_metadata');
        var m=String(suffix[0]).match(/^(?:_(\d+))?(\.jpe?g)$/i);
        var folders=fields.filter(function(x){return typeof x==='string' && x[0]==='/';});
        var prefixes=fields.filter(function(x){return typeof x==='string' && x[0]!=='/';});
        if(!m || folders.length!==1 || prefixes.length!==1 || !prefixes[0].trim() || /[\/\\\x00]/.test(prefixes[0]) || (!m[1] && counts[0]!==1))throw Error('invalid_metadata');
        var paths=[], start=m[1]?Number(m[1]):0, width=m[1]?m[1].length:0;
        if(!Number.isSafeInteger(start) || (m[1] && String(start+counts[0]-1).length>width))throw Error('counter_overflow');
        for(var i=0;i<counts[0];i++){var n=String(start+i);while(n.length<width)n='0'+n;paths.push(destination.replace(/\/$/,'')+'/'+prefixes[0]+(width?'_'+n:'')+m[2]);}
        return {paths:paths,folder:folders[0],prefix:prefixes[0],suffix:suffix[0],count:counts[0]};
    }
    function step(previous,settings,request,env) {
        var st=JSON.parse(JSON.stringify(previous||initialState())), r=request||{}, op=r.op||r.type, s=r.snapshot, now=env.now, action;
        function pause(code){st.phase='paused';st.status=code;st.errorCode=code;delete st.pending;}
        function result(extra){var out={ok:!st.errorCode,settings:settings,phase:st.phase,status:st.status,errorCode:st.errorCode||null};if(action)out.action=action;Object.keys(extra||{}).forEach(function(k){out[k]=extra[k];});return {state:st,response:out};}
        function reserve(type,plan){st.sequence=(st.sequence||0)+1;action={id:String(st.sequence)+'-'+String(now),type:type};if(type==='setDestination')action.destination=settings.destination;st.pending={action:action,pid:s.processId,plan:plan||null};st.since=now;}
        function safe(){return settings.enabled && !settings.dryRun && settings.destination && s && s.foreground===true && !s.blocked && s.saveTargetCount===1 && s.saveEnabled===true;}
        function samePlan(p){try{return JSON.stringify(metadata(s,settings.destination))===JSON.stringify(p);}catch(e){return false;}}
        if(op==='pause'){pause(['adapter_error','permission_denied','bridge_error'].indexOf(r.errorCode)>=0?r.errorCode:'adapter_error');return result();}
        if(op==='startup'||op==='reset'){var seq=st.sequence;st=initialState();st.sequence=seq||0;return result();}
        if(op==='canDispatch'){
            var p=st.pending, allowed=!!(p && p.action.id===r.actionId && safe() && p.pid===s.processId);
            if(allowed)allowed=p.action.type==='openSave'?view(s)==='choose':view(s)==='save' && samePlan(p.plan);
            if(allowed && p.action.type==='save')allowed=p.plan.folder===settings.destination && p.plan.paths.every(function(path){return !env.inspect(path).exists;});
            return result({allowed:allowed});
        }
        if(op==='reportAction'){
            if(!st.pending || st.pending.action.id!==r.actionId)return result({ok:false,errorCode:'unknown_action'});
            if(r.success!==true){pause(['destination_rejected','ui_changed','permission_denied'].indexOf(r.errorCode)>=0?r.errorCode:'dispatch_failed');return result();}
            var type=st.pending.action.type;delete st.pending;
            if(type==='save'){st.phase='verifying';st.status='verifying_files';st.since=now;}
            else st.status='awaiting_transition';
            return result();
        }
        if(op!=='tick')return result();
        if(st.phase==='paused')return result();
        if(!settings.enabled){st=initialState();st.status='disabled';return result();}
        if(s && s.blocked){pause('unsupported_view');return result();}
        if(st.phase==='verifying'){
            if(now-st.since>120){pause('export_timeout');return result();}
            var sizes=[], valid=st.plan.paths.every(function(path){var f=env.inspect(path);sizes.push(f.size);return f.exists && f.regular && f.jpeg && f.size>0;});
            if(valid && JSON.stringify(st.sizes)===JSON.stringify(sizes) && (view(s)==='idle'||view(s)==='choose')){st=initialState();st.phase='ready';st.status='saved';}
            else st.sizes=valid?sizes:null;
            return result();
        }
        var v=view(s);
        if(st.phase==='arming'){if(v==='idle' && !s.blocked){st.phase='ready';st.status='ready';}return result();}
        if(v==='idle'){delete st.pending;delete st.plan;st.phase='ready';st.status='ready';return result();}
        if(st.since!==undefined && (st.phase==='opening'||st.phase==='setting_destination') && now-st.since>30){pause('transition_timeout');return result();}
        if(s && s.foreground && s.blocked){pause('unsupported_view');return result();}
        if(settings.dryRun && s && s.foreground && !s.blocked && (v==='choose'||v==='save')){try{if(v==='save')metadata(s,settings.destination);st.status=v==='choose'?'dry_run_open_save':'dry_run_set_destination';}catch(e){pause(e.message);}return result();}
        if(s && s.foreground && !s.blocked && v==='save' && s.saveTargetCount!==1){pause('invalid_metadata');return result();}
        if(!safe())return result();
        if(st.pending)return result();
        if(v==='choose'){
            if(st.phase!=='ready')return result();
            st.phase='opening';st.status='opening_save';reserve('openSave');return result();
        }
        if(v!=='save'){pause('unsupported_view');return result();}
        var plan;try{plan=metadata(s,settings.destination);}catch(e){pause(e.message);return result();}
        if(plan.paths.some(function(p){return env.inspect(p).exists;})){pause('target_exists');return result();}
        if(st.phase==='setting_destination'){
            if(plan.folder!==settings.destination || !st.plan || plan.prefix!==st.plan.prefix || plan.suffix!==st.plan.suffix || plan.count!==st.plan.count){pause('destination_readback');return result();}
            st.plan=plan;st.status='saving';reserve('save',plan);return result();
        }
        st.plan=plan;st.phase='setting_destination';st.status='setting_destination';reserve('setDestination',plan);return result();
    }
    return {initialState:initialState,step:step,classify:view,metadata:metadata};
}());
if(typeof module!=='undefined')module.exports=AutoSaveCore;
