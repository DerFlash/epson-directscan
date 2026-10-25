const test=require('node:test'),a=require('node:assert/strict');
let C;try{C=require('../src/core.js')}catch{}
const settings={enabled:true,dryRun:false,destination:'/out'};
const idle={foreground:true,blocked:false,processId:7,windowTitle:'ScanSmart',captions:[],fields:[],suffixLabels:[],saveTargetCount:0,saveEnabled:false,noJob:true};
const choose={...idle,noJob:false,captions:['Aktion wählen'],saveTargetCount:1,saveEnabled:true};
const save={...choose,captions:['In Computereinstellungen speichern','Ausgewähltes Bild: 1 / 2'],fields:['/old','scan'],suffixLabels:['_001.jpg']};
function harness(){let state=C.initialState(),now=1,files={};return{get state(){return state},files,run(type,snapshot,extra={}){const x=C.step(state,settings,{type,snapshot,...extra},{now:now++,inspect:p=>files[p]||{exists:false}});state=x.state;return x.response},advance(n){now+=n}}}
test('engine exists',()=>a.equal(typeof C?.step,'function'));
test('startup pending stays arming; idle arms then chooses only once',()=>{let h=harness();a.equal(h.run('tick',choose).phase,'arming');a.equal(h.run('tick',idle).phase,'ready');let r=h.run('tick',choose);a.equal(r.action.type,'openSave');a.equal(h.run('tick',choose).action,undefined)});
test('full cycle verifies readback and stable JPEGs; repeat is rearmed',()=>{let h=harness();h.run('tick',idle);let x=h.run('tick',choose);h.run('reportAction',null,{actionId:x.action.id,success:true});x=h.run('tick',save);a.equal(x.action.type,'setDestination');h.run('reportAction',null,{actionId:x.action.id,success:true});x=h.run('tick',{...save,fields:['/out','scan']});a.equal(x.action.type,'save');h.run('reportAction',null,{actionId:x.action.id,success:true});for(let n of ['001','002'])h.files['/out/scan_'+n+'.jpg']={exists:true,regular:true,jpeg:true,size:10};a.equal(h.run('tick',idle).phase,'verifying');a.equal(h.run('tick',idle).phase,'ready');a.equal(h.run('tick',choose).action.type,'openSave')});
test('background, blocked, disabled and dry run never dispatch',()=>{for(let change of [{foreground:false},{blocked:true}]){let h=harness();h.run('tick',idle);a.equal(h.run('tick',{...choose,...change}).action,undefined)}let h=harness();h.run('tick',idle);settings.dryRun=true;a.equal(h.run('tick',choose).action,undefined);settings.dryRun=false});
test('invalid metadata, collisions and wrong readback pause',()=>{for(let change of [{fields:['/old','a/b']},{suffixLabels:['_001.jpg','.jpg']},{captions:['In Computereinstellungen speichern','/ 2','/ 3']},{suffixLabels:['.jpg']},{saveTargetCount:2}]){let h=harness();h.run('tick',idle);a.equal(h.run('tick',{...save,...change}).phase,'paused')}let h=harness();h.run('tick',idle);h.files['/out/scan_001.jpg']={exists:true};a.equal(h.run('tick',save).errorCode,'target_exists');h=harness();h.run('tick',idle);let x=h.run('tick',save);h.run('reportAction',null,{actionId:x.action.id,success:true});a.equal(h.run('tick',save).errorCode,'destination_readback')});
test('dispatch failure, restart and timeout never retry save',()=>{let h=harness();h.run('tick',idle);let x=h.run('tick',save);h.run('reportAction',null,{actionId:x.action.id,success:false});a.equal(h.run('tick',save).phase,'paused');h=harness();h.run('tick',idle);h.run('tick',choose);h.advance(31);a.equal(h.run('tick',choose).errorCode,'transition_timeout');a.equal(h.run('startup').phase,'arming')});
test('canDispatch validates exact pending plan and pid',()=>{let h=harness();h.run('tick',idle);let x=h.run('tick',save);a.equal(h.run('canDispatch',save,{actionId:x.action.id}).allowed,true);a.equal(h.run('canDispatch',{...save,processId:8},{actionId:x.action.id}).allowed,false)});
test('cancelled choice returns to ready without action',()=>{let h=harness();h.run('tick',idle);h.run('tick',choose);a.equal(h.run('tick',idle).phase,'ready')});
test('absent application arms safely with pid zero',()=>{let h=harness();a.equal(h.run('tick',{...idle,processId:0,foreground:false}).phase,'ready')});
test('dry run describes plan without reserving and unknown dialogs pause',()=>{let h=harness();h.run('tick',idle);settings.dryRun=true;a.equal(h.run('tick',save).status,'dry_run_set_destination');a.equal(h.state.pending,undefined);settings.dryRun=false;a.equal(h.run('tick',{...save,blocked:true}).phase,'paused')});
test('counter overflow and malformed JPEG never verify',()=>{let h=harness();h.run('tick',idle);a.equal(h.run('tick',{...save,suffixLabels:['_999.jpg']}).errorCode,'counter_overflow');h=harness();h.run('tick',idle);let x=h.run('tick',save);h.run('reportAction',null,{actionId:x.action.id,success:true});x=h.run('tick',{...save,fields:['/out','scan']});h.run('reportAction',null,{actionId:x.action.id,success:true});for(let n of ['001','002'])h.files['/out/scan_'+n+'.jpg']={exists:true,regular:false,jpeg:true,size:10};h.run('tick',idle);a.equal(h.run('tick',idle).phase,'verifying');h.advance(121);a.equal(h.run('tick',idle).errorCode,'export_timeout')});
test('simultaneous views reject; failure reports preserve only known codes',()=>{a.equal(C.classify({...save,captions:save.captions.concat('Aktion wählen')}),'blocked');for(let code of ['destination_rejected','ui_changed','permission_denied','private /path']){let h=harness();h.run('tick',idle);let x=h.run('tick',choose);a.equal(h.run('reportAction',null,{actionId:x.action.id,success:false,errorCode:code}).errorCode,code==='private /path'?'dispatch_failed':code)}});
test('closed Save with next Choose permits verification without action',()=>{let h=harness();h.run('tick',idle);let x=h.run('tick',save);h.run('reportAction',null,{actionId:x.action.id,success:true});x=h.run('tick',{...save,fields:['/out','scan']});h.run('reportAction',null,{actionId:x.action.id,success:true});for(let n of ['001','002'])h.files['/out/scan_'+n+'.jpg']={exists:true,regular:true,jpeg:true,size:10};h.run('tick',choose);let r=h.run('tick',choose);a.equal(r.phase,'ready');a.equal(r.action,undefined)});
test('blocked background snapshots pause visibly even while arming',()=>{let h=harness();a.equal(h.run('tick',{...idle,foreground:false,blocked:true,processId:0}).errorCode,'unsupported_view')});
test('transient observation failure waits without input and recovers on a fresh view',()=>{
    let h=harness();h.run('tick',idle);
    let r=h.run('observationError',null,{errorNumber:-1719});
    a.equal(r.phase,'ready');a.equal(r.status,'waiting_for_view');a.equal(r.action,undefined);
    a.equal(h.run('tick',choose).action.type,'openSave');
});
test('repeated observation errors time out and genuine permission errors retain the number',()=>{
    let h=harness();h.run('tick',idle);h.run('observationError',null,{errorNumber:-1728});h.advance(11);
    a.equal(h.run('observationError',null,{errorNumber:-1728}).errorCode,'ui_changed');
    h=harness();let r=h.run('observationError',null,{errorNumber:-1743});
    a.equal(r.errorCode,'permission_denied');a.equal(r.errorNumber,-1743);a.equal(r.action,undefined);
});
test('observation errors never retry a reserved or uncertain action',()=>{
    let h=harness();h.run('tick',idle);h.run('tick',choose);
    let r=h.run('observationError',null,{errorNumber:-1719});
    a.equal(r.phase,'paused');a.equal(r.errorCode,'ui_changed');a.equal(r.action,undefined);
});
test('new save view may finish loading but invalid formats never receive a save',()=>{
    let h=harness();h.run('tick',idle);let r=h.run('tick',choose);h.run('reportAction',null,{actionId:r.action.id,success:true});
    let loading={...save,fields:[],suffixLabels:['.pdf']};
    a.equal(h.run('tick',loading).status,'waiting_for_view');
    a.equal(h.run('tick',save).action.type,'setDestination');
    h=harness();h.run('tick',idle);r=h.run('tick',choose);h.run('reportAction',null,{actionId:r.action.id,success:true});
    h.run('tick',loading);h.advance(11);r=h.run('tick',loading);
    a.equal(r.errorCode,'invalid_metadata');a.equal(r.action,undefined);
});
test('one-page view requires the native single-page marker when the counter is hidden',()=>{
    const single={...save,captions:['In Computereinstellungen speichern'],singlePage:true};
    a.equal(C.metadata(single,'/out').count,1);
    a.throws(()=>C.metadata({...single,singlePage:false},'/out'),/invalid_metadata/);
});
