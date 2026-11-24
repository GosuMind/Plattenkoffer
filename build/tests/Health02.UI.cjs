const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {spawn} = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const profile = path.join(root, 'work/health02-ui-profile');
const browser = spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', [
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-port=9323', '--user-data-dir=' + profile, 'about:blank'
], {windowsHide:true, stdio:'ignore'});
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let socket;
(async () => {
  let pages;
  for (let attempt=0; attempt<60; attempt++) {
    try { pages = await (await fetch('http://127.0.0.1:9323/json')).json(); if(pages.length) break; } catch {}
    await pause(200);
  }
  assert(pages?.length, 'Headless browser did not start');
  socket = new WebSocket(pages.find(page => page.type === 'page').webSocketDebuggerUrl);
  await new Promise((resolve,reject) => {socket.onopen=resolve;socket.onerror=reject;});
  let sequence=0;
  const pending = new Map();
  const errors=[];
  socket.onmessage = ({data}) => {
    const message = JSON.parse(data);
    if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
    if (!message.id) return;
    const request = pending.get(message.id);
    pending.delete(message.id);
    if(message.error) request.reject(message.error); else request.resolve(message.result);
  };
  const call = (method,params={}) => new Promise((resolve,reject) => {
    const id=++sequence;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params}));
  });
  const evaluate = async expression => {
    const response = await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});
    if(response.exceptionDetails) throw new Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  };
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Page.addScriptToEvaluateOnNewDocument',{source:`
    window.chrome.webview={messages:[],handler:null,postMessage(data){this.messages.push(data);},addEventListener(type,handler){this.handler=handler;},dispatch(data){this.handler({data});}};
  `});
  await call('Emulation.setDeviceMetricsOverride',{width:1200,height:900,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate',{url:pathToFileURL(path.join(root,'setup/ui/index.html')).href});
  for(let attempt=0;attempt<50;attempt++) {
    if(await evaluate('!!window.chrome?.webview?.messages?.some(item => item.command === "ready")')) break;
    await pause(100);
  }
  for(let i=0;i<30;i++){if(await evaluate('!!document.querySelector("[data-health-special-dialog]")'))break;await pause(100);}
  await evaluate('document.querySelector(\'nav [data-command="health"]\').click()');
  const id='B'.repeat(64),musicPath='D:\\Test\\Musik\\DJ\\Sets\\Set\\part1.mp3';
  const state={type:'health',busy:false,status:'Teststand',options:{Root:'D:\\Test\\Musik',Storage:'D:\\Test\\Reports',BackupRoot:'D:\\Test\\Backups',CoverRoot:'D:\\Test\\Covers',QuarantineRoot:'D:\\Test\\Quarantine',FFmpeg:'D:\\Tools\\ffmpeg.exe',Probe:'D:\\Tools\\ffprobe.exe',VdjDatabase:'D:\\VDJ\\database.xml',BackupLimitGB:20},rows:[],summary:{Files:1,Tracks:0,Sets:1,Healthy:0,NeedsReview:0,AudioErrors:0,SemanticMatches:1},plans:[],backups:[],vdjBackups:[{id:'a'.repeat(32),path:'D:\\VDJ\\database.xml',state:'COMMITTED'}],quarantine:[{id:'q/'+id,path:musicPath,keeper:'D:\\keep.mp3',state:'COMMITTED'}],candidates:[{Path:'D:\\VDJ\\database.xml',Version:'2026',Entries:3,LibraryMatches:2,Writable:true},{Path:'D:\\Old\\database.xml',Version:'2025',Entries:1,LibraryMatches:0,Writable:false}],vdj:{Database:'D:\\VDJ\\database.xml',Version:'2026',Entries:3,Writable:true,ScannedAt:'2026-11-24T10:00:00Z',Rows:[{Index:0,Path:musicPath,Audio:{Artist:'Âme',Title:'Howling'},Current:{Author:'',Title:'audio'},Changes:{Author:'Âme',Title:'Howling'},Writable:true,Codes:['VDJ_METADATA_MISSING']},{Index:1,Path:'D:\\other.mp3',Audio:{},Current:{},Changes:{},Writable:false,Codes:['VDJ_DATABASE_ORPHAN_ENTRY']}]}};
  await evaluate('chrome.webview.dispatch('+JSON.stringify(state)+');document.querySelector(\'[data-health-tab="vdj"]\').click()');
  assert.equal(await evaluate('document.querySelector("[data-health-vdj]").hidden'),false);
  assert.equal(await evaluate('document.querySelector("[data-health-vdj-candidate]").value'),'');
  await evaluate('document.querySelector("[data-health-vdj-candidate]").value="D:\\\\VDJ\\\\database.xml";document.querySelector("[data-health-vdj-use]").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-options');
  await evaluate('document.querySelector("[data-health-vdj-select]").click();document.querySelector("[data-health-vdj-plan]").click()');
  assert.deepEqual(await evaluate('chrome.webview.messages.at(-1).indices'),[0]);
  const plan={Type:'VDJ',Id:'plan1',Database:'D:\\VDJ\\database.xml',Items:[{Path:musicPath,Before:{Author:{Value:''},Title:{Value:'audio'}},Changes:{Author:'Âme',Title:'Howling'}}]};
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-special-plan',plan})+')');
  assert.equal(await evaluate('document.querySelector("[data-health-special-dialog] button").disabled'),true);
  await evaluate('const c=document.querySelector("[data-health-special-approve]");c.checked=true;c.dispatchEvent(new Event("change"));document.querySelector("[data-health-special-dialog] button").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-special-approve');
  await evaluate('document.querySelector(\'[data-health-tab="quarantine"]\').click();document.querySelector("[data-health-quarantine-rows] button").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-quarantine-restore-preview');
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-special-restore',preview:{Id:'restore1',Type:'QUARANTINE_RESTORE',Path:musicPath}})+')');
  assert.equal(await evaluate('document.querySelector("[data-health-special-dialog] button").disabled'),true);
  await evaluate('document.querySelector("[data-health-special-dialog]").close()');
  const record={Id:id,Path:musicPath,Tags:{Artist:'DJ',Title:'Set'},Pk:{Artist:'DJ',Title:'Set'},Codes:[],Repairable:false,Covers:[],Resolved:{Values:{Artist:'DJ',Title:'Set'},Evidence:{},Conflicts:[]}};
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-record',record})+')');
  assert.equal(await evaluate('document.querySelector("[data-health-embed-cover]").disabled'),false);
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-cover-chosen',path:'D:\\generated.jpg'})+');const e=document.querySelector("[data-health-embed-cover]");e.checked=true;const origin=document.querySelector(\'select[aria-label="Herkunft des importierten Covers"]\');origin.value="KI-generiert";origin.dispatchEvent(new Event("change"));document.querySelector("[data-health-editor-form]").requestSubmit()');
  const request=await evaluate('chrome.webview.messages.at(-1)');assert.equal(request.requests[0].EmbedCover,true);assert.equal(request.requests[0].CoverOrigin,'KI-generiert');
  await evaluate('document.querySelector("[data-health-editor]").close()');
  for(const [width,height]of [[1200,900],[480,800]]){
    await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
    await evaluate('document.querySelector(\'[data-health-tab="vdj"]\').click()');
    assert(await evaluate('document.querySelector("[data-health]").scrollWidth <= document.querySelector("[data-health]").clientWidth+1'),'Health 02 overflow');
  }
  await call('Emulation.setDeviceMetricsOverride',{width:1200,height:900,deviceScaleFactor:1,mobile:false});
  const shot=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(root,'work/health02-vdj.png'),Buffer.from(shot.data,'base64'));
  assert.deepEqual(errors,[]);
  console.log('Health 02 UI OK: explicit database selection, per-entry VDJ preview and approval, quarantine restore approval, MP3 embed control and AI provenance, responsive layout.');
  await call('Browser.close');socket.close();
})().catch(error=>{console.error(error);socket?.close();browser.kill();process.exitCode=1});