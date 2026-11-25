const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {spawn} = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const profile = path.join(root, 'work/health-ui-profile');
const browser = spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', [
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-port=9321', '--user-data-dir=' + profile, 'about:blank'
], {windowsHide:true, stdio:'ignore'});
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let socket;
(async () => {
  let pages;
  for (let attempt=0; attempt<60; attempt++) {
    try { pages = await (await fetch('http://127.0.0.1:9321/json')).json(); if(pages.length) break; } catch {}
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
  for(let i=0;i<30;i++){if(await evaluate('!!document.querySelector("[data-health-editor]")'))break;await pause(100);}
  await evaluate('document.querySelector(\'nav [data-command="health"]\').click()');
  assert.equal(await evaluate('document.querySelector("[data-health]").hidden'),false);
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health');
  const row={id:'A'.repeat(64),path:'D:\\Musik\\WHTKD\\Tracks\\Say To Me\\audio.opus',kind:'Track',tags:{Artist:'',Title:''},codes:['MISSING_ARTIST','MISSING_TITLE','MISSING_JSON','MISSING_COVER'],notes:[],codec:'opus',container:'ogg',duration:252,rate:'48000',channels:2,size:4000000,bitrate:'139000',integrity:'PACKETS_CHECKED',repairable:true,coverCount:0};
  const data={type:'health',busy:false,status:'Scan abgeschlossen',options:{Root:'D:\\Musik',Probe:'D:\\Tools\\ffprobe.exe',FFmpeg:'D:\\Tools\\ffmpeg.exe',BackupRoot:'D:\\Backups',VideoSuffixes:['Official Video']},rows:[row],plans:[],backups:[],summary:{Files:1,Tracks:1,Sets:0,Healthy:0,NeedsReview:1,AudioErrors:0,MissingTags:1,MissingJson:1,MissingCovers:1,Conflicts:0,Duplicates:0,Bytes:4000000,FullyChecked:0,Score:null},scanState:'COMPLETED',lastScan:'2026-11-24T12:00:00Z'};
  await evaluate('chrome.webview.dispatch('+JSON.stringify(data)+')');
  assert.equal(await evaluate('document.querySelector("[data-health]").dataset.mode'),'simple');
  assert.equal(await evaluate('document.querySelectorAll("[data-health-simple-rows] article").length'),1);
  assert.equal(await evaluate('getComputedStyle(document.querySelector(".health-tabs")).display'),'none');
  await evaluate('chrome.webview.dispatch('+JSON.stringify({...data,busy:true,progress:{phase:'checking',done:1,total:5,current:row.path,step:'Tiefenscan'}})+')');
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-progress',phase:'checking',done:1,total:5,current:row.path,step:'Tiefenscan',filePercent:37})+')');
  await evaluate('document.querySelector(\'[data-health-mode="advanced"]\').click();document.querySelector(\'[data-health-mode="simple"]\').click()');
  assert.match(await evaluate('document.querySelector("[data-health-progress-text]").textContent'),/Diese Datei: 37 %/);
  assert.equal(await evaluate('document.querySelector("[data-health-progress]").hidden'),false);
  await evaluate('chrome.webview.dispatch('+JSON.stringify(data)+');document.querySelector(\'[data-health-mode="advanced"]\').click()');
  assert.equal(await evaluate('document.querySelectorAll("[data-health-rows] tr").length'),1);
  assert.match(await evaluate('document.querySelector("[data-health-summary]").textContent'),/1Audiodateien/);
  await evaluate('document.querySelector("[data-health-select]").click();document.querySelector("[data-health-batch]").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-plan');
  await evaluate('document.querySelector("[data-health-rows] button").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-record');
  const record={Id:row.id,Path:row.path,Tags:{Artist:'',Title:''},Pk:null,Codes:row.codes,Repairable:true,Covers:[],Resolved:{Values:{Artist:'WHTKD',Title:'Say To Me'},Conflicts:[],Evidence:{Artist:[{Source:'Ordnerstruktur',Value:'WHTKD',Confidence:'MEDIUM_CONFIDENCE'}],Title:[{Source:'Ordnerstruktur',Value:'Say To Me',Confidence:'MEDIUM_CONFIDENCE'}]}}};
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-record',record})+')');
  assert.equal(await evaluate('document.querySelector("[data-health-editor]").open'),true);
  for(const [width,height]of [[1200,900],[480,800]]){
    await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
    assert(await evaluate('document.querySelector("[data-health-editor]").getBoundingClientRect().width <= innerWidth'));
    assert(await evaluate('document.querySelector("[data-health]").scrollWidth <= document.querySelector("[data-health]").clientWidth+1'),'Health page overflow');
  }
  await evaluate('document.querySelector("[data-health-editor-form]").requestSubmit()');
  const request=await evaluate('chrome.webview.messages.at(-1)');assert.deepEqual(request.requests[0].Changes,{Artist:'WHTKD',Title:'Say To Me'});
  const plan={type:'health-plan',id:'p1',bytes:4000000,items:[{Path:row.path,Before:{Artist:'',Title:''},Changes:request.requests[0].Changes,Json:true,Sources:record.Resolved.Evidence}]};
  await evaluate('chrome.webview.dispatch('+JSON.stringify(plan)+')');
  assert.equal(await evaluate('document.querySelector("[data-health-plan-dialog] button").disabled'),true);
  await evaluate('const check=document.querySelector("[data-health-approve-check]");check.checked=true;check.dispatchEvent(new Event("change"));document.querySelector("[data-health-plan-dialog] button").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-approve');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).approved'),true);
  await evaluate('document.querySelector("[data-health-full]").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-scan');
  await evaluate('chrome.webview.dispatch('+JSON.stringify({...data,busy:true,operation:'scan'})+')');
  assert.equal(await evaluate('document.querySelector("[data-health-full]").disabled'),true);
  await evaluate('document.querySelector("[data-health-cancel]").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-cancel');
  await evaluate('chrome.webview.dispatch('+JSON.stringify({...data,busy:false,backups:[{id:'p1/'+row.id,path:row.path,state:'COMMITTED'}]})+');document.querySelector(\'[data-health-tab="backups"]\').click();document.querySelector("[data-health-backup-rows] input").click();document.querySelector("[data-health-restore]").click()');
  assert.equal(await evaluate('chrome.webview.messages.at(-1).command'),'health-restore-preview');
  await evaluate('chrome.webview.dispatch('+JSON.stringify({type:'health-restore-preview',id:'r1',paths:[row.path]})+')');
  assert.equal(await evaluate('document.querySelector("[data-health-restore-dialog] button").disabled'),true);
  await evaluate('document.querySelector("[data-health-restore-dialog]").close()');
  await call('Emulation.setDeviceMetricsOverride',{width:1200,height:900,deviceScaleFactor:1,mobile:false});
  await evaluate('document.querySelector(\'[data-health-tab="overview"]\').click()');
  const shot=await call('Page.captureScreenshot',{format:'png'});fs.writeFileSync(path.join(root,'work/health-center.png'),Buffer.from(shot.data,'base64'));
  assert.deepEqual(errors,[]);
  console.log('Health UI OK: integration, real metrics, selection, evidence editor, protected plan approval, cancel, restore preview, narrow dialogs.');
  await call('Browser.close');socket.close();
})().catch(error=>{console.error(error);socket?.close();browser.kill();process.exitCode=1});
