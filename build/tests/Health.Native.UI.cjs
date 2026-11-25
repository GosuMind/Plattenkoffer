// Attach only to an explicitly started, isolated full Windows app. No webview mock.
// Usage: node build/tests/Health.Native.UI.cjs <debug-port> <fixture-base>
// Fixture: music/Test/Tracks/Fehlende Angaben/audio.opus + matching info.json,
//          tagged tracks, music/Test/Sets/Langes Set/audio.opus (one hour), kaputt.opus.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../..');
const base=path.resolve(process.argv[3]||'');
assert(base.toLowerCase().startsWith((path.join(repo,'work')+path.sep).toLowerCase()),'Only explicit work/ fixtures allowed');
const port=Number(process.argv[2]);assert(port>1024&&port<65536);
const pause=ms=>new Promise(r=>setTimeout(r,ms));
let socket;
(async()=>{
  const pages=await(await fetch(`http://127.0.0.1:${port}/json`)).json();
  const page=pages.find(p=>p.url==='https://plattenkoffer.local/index.html');assert(page,'Full native app must already be running');
  socket=new WebSocket(page.webSocketDebuggerUrl);await new Promise((r,j)=>{socket.onopen=r;socket.onerror=j;});
  let id=0;const pending=new Map();
  socket.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}};
  const call=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});socket.send(JSON.stringify({id,method,params}));});
  const ev=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
  const click=selector=>ev(`document.querySelector(${JSON.stringify(selector)}).click()`);
  const wait=async(expression,label,ms=60000)=>{const end=Date.now()+ms;while(Date.now()<end){if(await ev(expression))return;await pause(80);}throw Error('Timeout: '+label+'; '+await ev(`document.querySelector('[data-health-status]').textContent`));};
  await call('Page.reload');await pause(300);await wait(`!!document.querySelector('[data-health-start]')`,'native document loaded');
  await ev(`window.pkNative={messages:[],latest:null};window.addEventListener('pk-health',e=>{pkNative.messages.push(e.detail);if(e.detail.type==='health')pkNative.latest=e.detail;});`);
  await click('nav [data-command="health"]');await wait('!!pkNative.latest','initial native response');
  const options=await ev('pkNative.latest.options');
  assert.equal(path.resolve(options.Root).toLowerCase(),path.join(base,'music').toLowerCase());
  for(const key of ['Storage','BackupRoot','QuarantineRoot','CoverRoot'])assert(path.resolve(options[key]).toLowerCase().startsWith((base+path.sep).toLowerCase()),key+' must stay in fixture');
  const music=options.Root;
  const scan=async(selector='[data-health-start]')=>{
    await ev('pkNative.messages=[]');await click(selector);
    assert.equal(await ev(`document.querySelector('[data-health-status]').textContent`),'Prüfung wird vorbereitet …');
  };
  const finished=()=>wait(`pkNative.messages.some((m,i)=>i>pkNative.messages.findIndex(p=>p.type==='health-progress'&&p.phase==='preparing')&&m.type==='health'&&!m.busy&&m.operation==='scan'&&m.status!=='Prüfung wird vorbereitet …')`,'native scan completion');
  await click('[data-health-mode="simple"]');await wait(`pkNative.latest.mode==='simple'`,'simple mode persisted');
  await scan();await click('[data-health-start]'); // disabled: no duplicate job
  await click('[data-health-mode="advanced"]');await click('[data-health-mode="simple"]');
  await finished();
  let result=await ev('pkNative.latest');assert.equal(result.summary.Files,5);assert.equal(result.summary.AudioErrors,1);
  assert.equal(await ev(`pkNative.messages.filter(m=>m.type==='health-progress'&&m.status==='Prüfung wird vorbereitet …'&&!m.step).length`),1);
  assert(await ev(`pkNative.messages.some(m=>m.phase==='checking'&&m.current&&m.total===5)`),'Native worker progress missing');
  const missing=result.rows.find(r=>r.path.includes('Fehlende Angaben'));assert(missing);
  await ev(`Array.from(document.querySelectorAll('[data-health-groups] button')).find(b=>b.textContent.includes('Fehlende Musikangaben')).click()`);
  await click(`.health-simple-row[data-health-id="${missing.id}"] input`);
  await click('[data-health-mode="advanced"]');
  assert(await ev(`document.querySelector('tr[data-health-id="${missing.id}"] input').checked`));
  await ev(`document.querySelector('[data-health-deep]').checked=true`);await scan('[data-health-full]');
  await wait(`pkNative.messages.some(m=>(m.step||'').startsWith('Tiefenscan:')&&m.current.includes('Langes Set'))`,'long native deep scan');
  await wait(`pkNative.messages.some(m=>m.filePercent>0&&m.filePercent<100)`,'measured file progress');
  await click('[data-health-mode="simple"]');
  assert(await ev(`!document.querySelector('[data-health-progress]').hidden`),'Progress lost on mode change');
  await click('[data-health-cancel]');await finished();
  assert.equal(await ev('pkNative.latest.scanState'),'CANCELLED');
  await click('[data-health-mode="advanced"]');await scan('[data-health-resume]');await finished();
  assert.equal(await ev('pkNative.latest.scanState'),'COMPLETED');
  const reportPath=path.join(options.Storage,'scan.json');
  const before=JSON.parse(fs.readFileSync(reportPath,'utf8'));
  const infoPath=path.join(path.dirname(missing.path),'info.json');
  const info=JSON.parse(fs.readFileSync(infoPath,'utf8').replace(/^\uFEFF/,''));info.publisher='Native Test Label';fs.writeFileSync(infoPath,JSON.stringify(info));
  await scan('[data-health-incremental]');await finished();
  const after=JSON.parse(fs.readFileSync(reportPath,'utf8'));
  assert.notEqual(after.Records.find(r=>r.Id===missing.id).ScannedAt,before.Records.find(r=>r.Id===missing.id).ScannedAt,'Changed source must be checked again');
  const unchanged=before.Records.find(r=>r.Tags.Title==='Langes Set');assert.equal(after.Records.find(r=>r.Id===unchanged.Id).ScannedAt,unchanged.ScannedAt,'Unchanged result should be reused');
  const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const original=hash(missing.path);
  await click('[data-health-mode="simple"]');
  await click(`.health-simple-row[data-health-id="${missing.id}"] button`);
  await wait(`document.querySelector('[data-health-editor]').open`,'guided source editor');
  assert(await ev(`document.querySelector('[data-health-editor]').textContent.includes('Quelle')`));
  await ev(`document.querySelector('[data-health-editor-form]').requestSubmit()`);
  await wait(`document.querySelector('[data-health-plan-dialog]').open`,'real repair preview');
  assert.equal(await ev(`document.querySelector('[data-health-plan-dialog] button').disabled`),true);
  await ev(`{const c=document.querySelector('[data-health-approve-check]');c.checked=true;c.dispatchEvent(new Event('change'));document.querySelector('[data-health-plan-dialog] button').click();}`);
  await wait(`pkNative.latest.operation==='repair'&&!pkNative.latest.busy&&pkNative.latest.dirty`,'native repair');
  assert.notEqual(hash(missing.path),original,'Repair should fill missing tags');
  assert.match(await ev('pkNative.latest.status'),/1 erfolgreich/);
  await click('[data-health-simple-backups]');
  await ev(`Array.from(document.querySelectorAll('[data-health-backup-rows] label')).find(x=>x.textContent.includes('Fehlende Angaben')&&!x.querySelector('input').disabled).querySelector('input').click()`);
  await click('[data-health-restore]');await wait(`document.querySelector('[data-health-restore-dialog]').open`,'native restore preview');
  await ev(`{const c=document.querySelector('[data-health-restore-dialog] input');c.checked=true;c.dispatchEvent(new Event('change'));document.querySelector('[data-health-restore-dialog] button').click();}`);
  await wait(`pkNative.latest.operation==='restore'&&!pkNative.latest.busy`,'native restore');assert.equal(hash(missing.path),original,'Original bytes must be restored');
  // Error and empty states through the same normal buttons, fixture paths only.
  const tool=options.Probe;fs.renameSync(tool,tool+'.native-test');
  try{await scan('[data-health-full]');await finished();assert.match(await ev('pkNative.latest.status'),/Prüfprogramm fehlt/);assert(await ev('!!pkNative.latest.detail'));}finally{fs.renameSync(tool+'.native-test',tool);}
  fs.renameSync(music,music+'.native-test');
  try{await scan('[data-health-full]');await finished();assert.match(await ev('pkNative.latest.status'),/Musikordner ist nicht erreichbar/);}finally{fs.renameSync(music+'.native-test',music);}
  const setRoot=async folder=>{await ev(`document.querySelector('[data-health-options] input[name=Root]').value=${JSON.stringify(folder)};document.querySelector('[data-health-options]').requestSubmit()`);await wait(`pkNative.latest.options.Root===${JSON.stringify(folder)}`,'save native folder');};
  const empty=path.join(base,'empty');fs.mkdirSync(empty,{recursive:true});await setRoot(empty);await scan('[data-health-full]');await finished();assert.match(await ev('pkNative.latest.status'),/Keine unterstützten Musikdateien/);
  await setRoot(music);await click('[data-health-mode="simple"]');await scan();await finished();
  await call('Page.captureScreenshot').then(r=>fs.writeFileSync(path.join(base,'native-final.png'),Buffer.from(r.data,'base64')));
  fs.writeFileSync(path.join(base,'native-evidence.json'),JSON.stringify(await ev('pkNative.messages'),null,2));
  console.log('PASS native Windows app: immediate ack, duplicate prevention, actual queue/runspace/results, both modes/selection, one-hour deep progress/cancel/resume, changed-file reuse, guided approval/backup/exact restore, missing tool/root, corrupt file, empty folder.');
  socket.close();
})().catch(e=>{console.error(e);socket?.close();process.exitCode=1;});
