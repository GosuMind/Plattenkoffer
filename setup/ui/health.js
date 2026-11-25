(() => {
  'use strict';
  const root=document.getElementById('pk-concept');
  const q=s=>root.querySelector(s);
  const send=(command,values={})=>window.chrome.webview.postMessage({command,...values});
  const el=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=String(text);return n;};
  const action=(text,fn)=>{const n=el('button',text);n.type='button';n.onclick=fn;return n;};
  const labels={Artist:'Interpret / DJ',Title:'Titel / Setname',Album:'Album',AlbumArtist:'Album-Interpret',Version:'Version / Remix',Label:'Label / Publisher',Genre:'Genre',Year:'Jahr',Date:'Veröffentlichungsdatum',Series:'Set-Reihe',Event:'Veranstaltung',Location:'Location',TrackNumber:'Tracknummer',SourceUrl:'Quell-URL',VideoId:'Video-ID',ISRC:'ISRC'};
  const codeLabels={METADATA_EXACT_MATCH:'Metadaten exakt konsistent',METADATA_SEMANTIC_MATCH:'Metadaten semantisch konsistent',METADATA_CONFLICT:'Echter Metadatenwiderspruch',METADATA_REVIEW_REQUIRED:'Metadatenprüfung offen',AUDIO_METADATA_MISSING:'Audio-Tags fehlen',AUDIO_METADATA_CONFLICT:'Audio-/PK-Konflikt',UNICODE_REVIEW_REQUIRED:'Zeichenfolge manuell prüfen',HEALTHY:'Fehlerfrei, vollständig geprüft',MISSING_ARTIST:'Interpret fehlt',MISSING_TITLE:'Titel fehlt',INVALID_TAG:'Ungültiges Tag',TAG_MISMATCH:'Quellen widersprechen sich',MISSING_JSON:'PK-JSON fehlt',INVALID_JSON:'JSON fehlerhaft',JSON_MISMATCH:'JSON / Tags widersprüchlich',MISSING_COVER:'Cover fehlt',INVALID_COVER:'Cover nicht lesbar',EMBEDDED_COVER_MISSING:'Kein eingebettetes Cover',DUPLICATE_AUDIO:'Identische Datei / Audiodaten',POSSIBLE_DUPLICATE:'Mögliches Duplikat',INVALID_PATH:'Ordnerstruktur prüfen',GENERIC_FILENAME:'Generischer Dateiname (Hinweis)',AUDIO_ERROR:'Audio technisch auffällig',UNSUPPORTED_FORMAT:'Nur lesend unterstützt',MANUAL_REVIEW:'Manuell prüfen'};
  let state={rows:[],backups:[],plans:[],busy:false},tab='overview',page=0,record=null,planToken='',restoreToken='',coverPath='',coverOrigin='Manueller Coverimport';
  const selected=new Set(),backupSelected=new Set();
  let coverBatchIds=[];
  let mode='simple',simpleGroup='all',deepInitialized=false;
  const groups=[
    {id:'missing',label:'Fehlende Musikangaben',hint:'Hinweis · Angaben ergänzen',codes:['MISSING_ARTIST','MISSING_TITLE','AUDIO_METADATA_MISSING','MISSING_JSON']},
    {id:'conflicts',label:'Widersprüchliche Angaben',hint:'Prüfbedarf · Quellen vergleichen',codes:['METADATA_CONFLICT','AUDIO_METADATA_CONFLICT','JSON_MISMATCH','TAG_MISMATCH','INVALID_TAG','AUDIO_METADATA_INVALID','UNICODE_REVIEW_REQUIRED']},
    {id:'covers',label:'Fehlende Cover',hint:'Hinweis · Cover auswählen',codes:['MISSING_COVER']},
    {id:'duplicates',label:'Mögliche doppelte Dateien',hint:'Hinweis · Dateien vergleichen, bevor du sie archivierst',codes:['DUPLICATE_AUDIO','POSSIBLE_DUPLICATE']},
    {id:'reading',label:'Probleme beim Lesen',hint:'Fehler / Prüfproblem · Details ansehen',codes:['AUDIO_ERROR','INVALID_JSON','INVALID_COVER','TOOL_ENCODING_ERROR']},
    {id:'other',label:'Weitere Hinweise',hint:'Hinweis · Details prüfen',codes:['INVALID_PATH','GENERIC_FILENAME','EMBEDDED_COVER_MISSING','UNSUPPORTED_FORMAT','MANUAL_REVIEW','METADATA_REVIEW_REQUIRED']}
  ];
  const rowGroups=row=>groups.filter(g=>row.codes.some(c=>g.codes.includes(c)));
  function setMode(value,persist=false){
    mode=value==='advanced'?'advanced':'simple';q('[data-health]').dataset.mode=mode;
    for(const b of root.querySelectorAll('[data-health-mode]'))b.setAttribute('aria-pressed',String(b.dataset.healthMode===mode));
    if(mode==='simple')setTab('overview');
    renderRows();if(persist)send('health-mode',{mode});
  }
  function renderSimple(){
    q('[data-health-folder]').textContent=state.options?.Root||'Musikordner wird geladen …';
    q('[data-health-folder-change]').disabled=state.busy;
    q('[data-health-start]').disabled=state.busy;
    q('[data-health-diagnosis]').hidden=!state.detail;q('[data-health-detail]').textContent=state.detail||'';
    const box=q('[data-health-groups]');box.replaceChildren();
    if(!state.summary)return;
    const all=action('Alle '+state.rows.length+' geprüften Dateien',()=>{simpleGroup='all';page=0;renderRows();});all.setAttribute('aria-pressed',String(simpleGroup==='all'));box.append(all);
    for(const g of groups){
      const count=state.rows.filter(row=>rowGroups(row).includes(g)).length;
      const b=action('',()=>{simpleGroup=g.id;page=0;renderRows();});b.className='health-metric';b.setAttribute('aria-pressed',String(simpleGroup===g.id));b.append(el('strong',count),el('span',g.label),el('small',g.hint));box.append(b);
    }
  }
  const size=value=>value==null?'–':Number(value)>=1073741824?(Number(value)/1073741824).toFixed(2)+' GB':(Number(value)/1048576).toFixed(1)+' MB';
  const stamp=value=>value?new Date(value).toLocaleString('de-DE'):'Noch kein vollständiger Scan';
  const textCodes=codes=>(codes||[]).map(code=>codeLabels[code]||code).join(' · ');
  const progress=data=>{
    state.progress={...(state.progress||{}),...data};data=state.progress;
    q('[data-health-current]').textContent=state.busy?(data.current||''):'';
    const p=q('[data-health-progress]');p.hidden=!state.busy;
    const total=Number(data.total)||0,done=Number(data.done)||0;
    p.max=Math.max(1,total);
    if(total&&data.phase==='checking')p.value=done;else p.removeAttribute('value');
    q('[data-health-progress-text]').textContent=state.busy?(total&&data.phase==='checking'?Math.floor(100*done/total)+' % · Datei '+Math.min(done+1,total)+' von '+total+' · ':'')+(data.step||'Prüfung läuft …')+(data.filePercent!=null?' · Diese Datei: '+data.filePercent+' %':''):'';
    q('[data-health-progress-text]').classList.toggle('health-active',state.busy);
    if(data.status)q('[data-health-status]').textContent=data.status;
  };
  function matches(row,filter){
    if(filter==='all')return true;
    if(['Track','Set'].includes(filter))return row.kind===filter;
    if(filter==='missing')return row.codes.some(c=>['MISSING_ARTIST','MISSING_TITLE'].includes(c));
    if(filter==='conflicts')return row.codes.some(c=>['JSON_MISMATCH','TAG_MISMATCH'].includes(c));
    if(filter==='duplicates')return row.codes.some(c=>['DUPLICATE_AUDIO','POSSIBLE_DUPLICATE'].includes(c));
    if(filter==='vdj')return !!row.tags?.Artist&&!!row.tags?.Title;
    return row.codes.includes(filter);
  }
  function filtered(){
    const needle=q('[data-health-search]').value.toLocaleLowerCase('de');
    return state.rows.filter(row=>(mode==='simple'?(simpleGroup==='all'||rowGroups(row).some(g=>g.id===simpleGroup)):matches(row,q('[data-health-filter]').value))&&[row.path,...Object.values(row.tags||{})].join(' ').toLocaleLowerCase('de').includes(needle));
  }
  function renderRows(){
    const rows=filtered();page=Math.min(page,Math.max(0,Math.ceil(rows.length/100)-1));
    const body=q('[data-health-rows]');body.replaceChildren();
    const simple=q('[data-health-simple-rows]');simple.replaceChildren();
    for(const row of rows.slice(page*100,(page+1)*100)){
      const card=el('article');card.className='health-simple-row';card.dataset.healthId=row.id;
      const pick=el('input');pick.type='checkbox';pick.checked=selected.has(row.id);pick.setAttribute('aria-label',(row.tags?.Title||row.path)+' auswählen');pick.onchange=()=>{pick.checked?selected.add(row.id):selected.delete(row.id);renderRows();};
      const info=el('div');info.append(el('strong',row.tags?.Title||'Titel fehlt'),el('p',row.tags?.Artist||'Interpret / DJ fehlt'));
      const problems=rowGroups(row);info.append(el('p',problems.length?problems.map(g=>g.label).join(' · '):'Keine offenen Hinweise in diesen Gruppen.'));
      if(row.codes.includes('AUDIO_ERROR'))info.append(el('small','Die Audiodatei konnte nicht vollständig gelesen werden. Diagnose prüfen; keine automatische Audioreparatur.'));
      card.append(pick,info,action('Details und nächste Schritte',()=>{coverBatchIds=[];send('health-record',{id:row.id});}));simple.append(card);
      const tr=el('tr');tr.dataset.healthId=row.id;
      const check=el('input');check.type='checkbox';check.checked=selected.has(row.id);check.setAttribute('aria-label',(row.tags?.Title||row.path)+' auswählen');
      check.onchange=()=>{check.checked?selected.add(row.id):selected.delete(row.id);updateSelection();};tr.append(el('td'));tr.lastChild.append(check);
      for(const field of ['Artist','Title','Version','Album','Genre','Year'])tr.append(el('td',row.tags?.[field]||'–'));
      const duration=row.duration?Math.floor(row.duration/60)+':'+String(Math.floor(row.duration%60)).padStart(2,'0'):'–';
      for(const value of [row.codec?row.path.split('.').at(-1).toUpperCase()+' / '+row.codec+(typeof row.lossless==='boolean'?(row.lossless?' · verlustfrei':' · verlustbehaftet'):''):'–',row.bitrate?Math.round(Number(row.bitrate)/1000)+' kbit/s':'–',duration,row.rate?(Number(row.rate)/1000)+' kHz / '+row.channels:'–',size(row.size),row.coverCount+' extern'+(row.embeddedCover?' + eingebettet':''),textCodes(row.codes),row.integrity==='DECODE_CHECKED'?'Vollständig dekodiert':row.integrity==='PACKETS_CHECKED'?'Pakete geprüft · kein Tiefenscan':row.integrity,row.path])tr.append(el('td',value));
      const cell=el('td');cell.append(action(row.repairable?'Prüfen / bearbeiten':'Prüfen / Cover',()=>{coverBatchIds=[];send('health-record',{id:row.id});}));tr.append(cell);body.append(tr);
    }
    q('[data-health-page]').textContent=rows.length+' Dateien · Seite '+(page+1)+' / '+Math.max(1,Math.ceil(rows.length/100));
    q('[data-health-prev]').disabled=!page;q('[data-health-next]').disabled=(page+1)*100>=rows.length;
    updateSelection();
    if(!rows.length)simple.append(el('p',state.summary?'Keine Dateien in dieser Auswahl.':'Noch keine Ergebnisse. Starte mit „Sammlung prüfen“.'));
    for(const b of q('[data-health-groups]').querySelectorAll('button'))b.setAttribute('aria-pressed',String(b.textContent.startsWith('Alle ')?simpleGroup==='all':groups.find(g=>b.textContent.includes(g.label))?.id===simpleGroup));
  }
  function updateSelection(){
    q('[data-health-selected]').textContent=selected.size+' ausgewählt';
    for(const selector of ['[data-health-batch]','[data-health-json]','[data-health-quarantine-plan]','[data-health-cover-batch]'])q(selector).disabled=state.busy||!selected.size||state.dirty;
  }
  function render(){
    if(!deepInitialized&&typeof state.options?.Deep==='boolean'){q('[data-health-deep]').checked=state.options.Deep;deepInitialized=true;}
    q('[data-health-status]').textContent=state.status||'';
    q('[data-health-lastscan]').textContent=state.lastScan?'Letzte Prüfung: '+stamp(state.lastScan)+(state.scanState==='CANCELLED'?' · Abgebrochen, Teilergebnisse':'')+(state.dirty?' · Nach Änderungen bitte neu prüfen.':''):'';
    for(const control of root.querySelectorAll('[data-health-full],[data-health-incremental],[data-health-resume],[data-health-deep],[data-health-options] input,[data-health-options] button'))control.disabled=state.busy;
    q('[data-health-cancel]').disabled=!state.busy;
    progress(state.progress||{});
    const form=q('[data-health-options]');
    for(const [key,value]of Object.entries(state.options||{}))if(form.elements.namedItem(key))form.elements.namedItem(key).value=Array.isArray(value)?value.join(', '):value;
    const metrics=q('[data-health-summary]');metrics.replaceChildren();
    const entries=[['Files','Audiodateien'],['SemanticMatches','Semantisch konsistent'],['Tracks','Tracks'],['Sets','DJ-Sets'],['Healthy','Fehlerfrei · tiefengeprüft'],['NeedsReview','Mit Hinweisen / Prüfbedarf'],['AudioErrors','Technisch auffällig'],['MissingTags','Fehlende Audio-Tags'],['MissingJson','Fehlendes PK-JSON'],['MissingCovers','Fehlende Cover'],['Conflicts','Metadatenkonflikte'],['Duplicates','Duplikatverdacht']];
    for(const [key,label]of entries){const box=el('div');box.className='health-metric';box.append(el('strong',state.summary?state.summary[key]:'–'),el('span',label));metrics.append(box);}
    const bytes=el('div');bytes.className='health-metric';bytes.append(el('strong',state.summary?size(state.summary.Bytes):'–'),el('span','Speicherverbrauch'));metrics.append(bytes);
    for(const [key,label]of [['Open','Offene Reparaturaufträge'],['Successful','Erfolgreiche Reparaturen · Historie']]){const box=el('div');box.className='health-metric';box.append(el('strong',state.activity?.[key]??'–'),el('span',label));metrics.append(box);}
    q('[data-health-score]').textContent=state.summary?(state.summary.Score==null?'Noch kein Health Score. Dafür ist ein vollständiger Tiefenscan nötig.':'Health Score '+state.summary.Score+' % · '+state.summary.Healthy+' / '+state.summary.FullyChecked+' vollständig dekodierte Dateien ohne offene Prüfhinweise.')+' Letzter Scan: '+stamp(state.lastScan)+' · '+state.scanState:'';
    q('[data-health-warning]').textContent=[...(state.warnings||[]),state.dirty?'Die angezeigten Scanwerte stammen von vor den Änderungen. Bitte neu scannen.':'',state.activity?.LastBackup?'Letzte protokollierte Sicherung: '+stamp(state.activity.LastBackup):''].filter(Boolean).join(' ');
    renderSimple();renderRows();renderHistory();
  }
  function renderHistory(){
    q('[data-health-backup-usage]').textContent='Backups: '+size(state.backupBytes||0)+' · Limit: '+(state.options?.BackupLimitGB?state.options.BackupLimitGB+' GB':'unbegrenzt')+' · Keine automatische Löschung';
    const plans=q('[data-health-plans]');plans.replaceChildren();
    for(const plan of state.plans||[]){const row=el('div',stamp(plan.date)+' · '+plan.count+' Dateien · '+plan.state+' · '+plan.success+' erfolgreich / '+plan.failed+' fehlgeschlagen');row.className='health-history-row';if(plan.success<plan.count){const retry=action('Restliche Dateien neu planen',()=>send('health-resume-plan',{id:plan.id}));retry.disabled=state.busy||state.dirty;row.append(retry);}plans.append(row);}
    if(!state.plans?.length)plans.append(el('p','Noch keine Reparaturaufträge.'));
    const backups=q('[data-health-backup-rows]');backups.replaceChildren();
    for(const item of state.backups||[]){
      const row=el('label');row.className='health-history-row';const check=el('input');check.type='checkbox';check.checked=backupSelected.has(item.id);check.disabled=['RESTORED','FAILED','ROLLED_BACK'].includes(item.state);
      check.onchange=()=>check.checked?backupSelected.add(item.id):backupSelected.delete(item.id);
      row.append(check,el('span',stamp(item.date)+' · '+item.state+' · '+item.path+(item.error?' · '+item.error:'')));backups.append(row);
    }
    if(!state.backups?.length)backups.append(el('p','Noch keine Reparaturbackups.'));
  }
  const setTab=value=>{
    tab=value;
    const secondary=['vdj','quarantine','backups','repairs','reports'].includes(tab);
    q('[data-health-summary]').hidden=secondary;q('[data-health-score]').hidden=secondary;
    for(const button of root.querySelectorAll('[data-health-tab]'))button.setAttribute('aria-pressed',String(button.dataset.healthTab===tab));
    const sections={'[data-health-history]':'repairs','[data-health-backups]':'backups','[data-health-reports]':'reports','[data-health-vdj]':'vdj','[data-health-quality-note]':'quality','[data-health-quarantine]':'quarantine'};
    for(const [selector,name]of Object.entries(sections))q(selector).hidden=tab!==name;
    q('[data-health-library]').hidden=['repairs','backups','reports','vdj','quarantine'].includes(tab);
    q('[data-health-filter]').value=({metadata:'missing',covers:'MISSING_COVER',integrity:'AUDIO_ERROR',duplicates:'duplicates',paths:'INVALID_PATH',vdj:'vdj'})[tab]||'all';
    page=0;renderRows();
  };
  for(const button of root.querySelectorAll('[data-health-tab]'))button.onclick=()=>setTab(button.dataset.healthTab);
  q('[data-health-search]').oninput=()=>{page=0;renderRows();};q('[data-health-filter]').onchange=()=>{page=0;renderRows();};
  q('[data-health-prev]').onclick=()=>{page--;renderRows();};q('[data-health-next]').onclick=()=>{page++;renderRows();};
  q('[data-health-select]').onclick=()=>{filtered().forEach(row=>selected.add(row.id));renderRows();};
  q('[data-health-clear]').onclick=()=>{selected.clear();renderRows();};
  function startScan(incremental=false,deep=q('[data-health-deep]').checked){
    if(state.busy)return;
    state.busy=true;state.status='Prüfung wird vorbereitet …';state.progress={phase:'preparing',done:0,total:0,current:'',step:state.status};render();
    try{send('health-scan',{deep,incremental});}catch{state.busy=false;state.status='Die Verbindung zur App fehlt. Plattenkoffer neu öffnen und erneut versuchen.';render();}
  }
  q('[data-health-full]').onclick=()=>startScan(false);
  q('[data-health-incremental]').onclick=()=>startScan(true);
  q('[data-health-resume]').onclick=()=>startScan(true);
  q('[data-health-start]').onclick=()=>startScan(false,false);
  q('[data-health-folder-change]').onclick=()=>send('health-folder');
  for(const b of root.querySelectorAll('[data-health-mode]'))b.onclick=()=>setMode(b.dataset.healthMode,true);
  q('[data-health-simple-backups]').onclick=()=>{setMode('advanced',true);setTab('backups');};
  q('[data-health-more]').onclick=()=>{setMode('advanced',true);setTab('overview');};
  q('[data-health-cancel]').onclick=()=>send('health-cancel');
  q('[data-health-options]').onsubmit=event=>{event.preventDefault();send('health-options',{values:Object.fromEntries(new FormData(event.target))});};
  q('[data-health-batch]').onclick=()=>send('health-plan',{requests:[...selected].map(Id=>({Id}))});
  q('[data-health-json]').onclick=()=>send('health-plan',{requests:[...selected].map(Id=>({Id,Json:true}))});
  q('[data-health-quarantine-plan]').onclick=()=>send('health-quarantine-plan',{ids:[...selected]});
  q('[data-health-cover-batch]').onclick=()=>{coverBatchIds=[...selected];if(coverBatchIds.length)send('health-record',{id:coverBatchIds[0]});};
  q('[data-health-export]').onclick=()=>send('health-export');q('[data-health-open-reports]').onclick=()=>send('health-reports');
  q('[data-health-export-repairs]').onclick=()=>send('health-export-repairs');
  q('[data-health-restore]').onclick=()=>send('health-restore-preview',{ids:[...backupSelected]});
  const editor=el('dialog');editor.dataset.healthEditor='';editor.setAttribute('aria-label','Metadaten und Quellen vergleichen');root.append(editor);
  editor.addEventListener('close',()=>{coverBatchIds=[];});
  function openEditor(value){
    record=value;coverPath='';coverOrigin='Manueller Coverimport';editor.replaceChildren();
    const header=el('header');header.append(el('h2','Angaben prüfen und ergänzen'),action('Schließen',()=>editor.close()));editor.append(header);
    const details=el('details');details.append(el('summary','Datei und technische Prüfergebnisse'),el('p',record.Path),el('p',textCodes(record.Codes)));editor.append(details);
    const related=state.rows.find(r=>r.id===record.Id);editor.append(el('p',related?rowGroups(related).map(g=>g.label+': '+g.hint).join('. '):'Vorhandene Werte und Quellen vergleichen.'));
    editor.append(el('p','Wähle die gewünschten Felder und prüfe den neuen Wert und seine Quelle. Fehlende Informationen kannst du offen lassen. Markierte Musikangaben ändern die Audiodatei und gleichen die Plattenkoffer-Angaben ab. „Plattenkoffer-Angaben ergänzen“ füllt zusätzliche fehlende Sammlungsangaben aus vorhandenen Musikangaben. Vor jeder Übernahme folgt eine Vorschau mit Sicherung.'));
    if(!record.Repairable)editor.append(el('p','Das Audioformat ist für Änderungen an Musikangaben noch nicht freigegeben. Vorhandene Angaben bleiben lesbar; zulässige Cover- und Sammlungsaktionen sind weiterhin verfügbar.'));
    if(coverBatchIds.length>1)editor.append(el('p','Gemeinsames Cover für '+coverBatchIds.length+' ausgewählte Dateien. Audio-Tags bleiben unverändert. Einbettung ist nur bei einer reinen MP3-Auswahl möglich.'));
    if(record.Notes?.length)editor.append(el('p',record.Notes.join(' ')));
    if(!record.Resolved){editor.append(el('p','Keine belastbare Metadatenanalyse verfügbar.'));editor.showModal();return;}
    const form=el('form');form.dataset.healthEditorForm='';
    const scroll=el('div');scroll.className='health-editor-fields';const table=el('table');
    const headings=table.createTHead().insertRow();for(const text of ['Ändern','Angabe','In der Musikdatei','Plattenkoffer / Quellen','Vorgeschlagener neuer Wert'])headings.append(el('th',text));
    const body=table.createTBody();
    for(const [field,label]of Object.entries(labels)){
      const row=body.insertRow();const check=el('input');check.type='checkbox';check.dataset.healthField=field;check.setAttribute('aria-label',label+' ändern');check.disabled=!record.Repairable;row.insertCell().append(check);row.insertCell().textContent=label;row.insertCell().textContent=record.Tags?.[field]||'–';
      const sources=row.insertCell();sources.append(el('small','PK: '+(record.Pk?.[field]||'–')));
      const input=el('input');input.name=field;input.value=record.Resolved.Values?.[field]||record.Tags?.[field]||'';input.disabled=!record.Repairable;input.maxLength=2000;input.setAttribute('aria-label',label+' neuer Wert');
      if(record.Resolved.Conflicts?.includes(field))sources.append(el('small','KONFLIKT · Wert ausdrücklich auswählen'));
      for(const source of record.Resolved.Evidence?.[field]||[]){const confidence=({HIGH_CONFIDENCE:'gut belegt',MEDIUM_CONFIDENCE:'bitte prüfen',LOW_CONFIDENCE:'unsicher',VERIFIED:'bestätigt'})[source.Confidence]||source.Confidence||'Quelle prüfen';const choose=action(source.Source+': '+source.Value+' · '+confidence,()=>{input.value=source.Value;check.checked=true;});choose.disabled=!record.Repairable;sources.append(choose);}
      input.oninput=()=>{check.checked=true;};row.insertCell().append(input);
      if(!record.Tags?.[field]&&input.value&&!record.Resolved.Conflicts?.includes(field)&&['Artist','Title'].includes(field))check.checked=record.Repairable;
    }
    scroll.append(table);form.append(scroll);
    const json=el('label');json.className='check-line';const jsonCheck=el('input');jsonCheck.type='checkbox';jsonCheck.name='rebuildJson';jsonCheck.checked=record.Codes.includes('MISSING_JSON');json.append(jsonCheck,document.createTextNode('Plattenkoffer-Angaben ergänzen (aus den Musikangaben; eigene Zusatzfelder bleiben erhalten)'));form.append(json);
    const coverBox=el('section');coverBox.className='settings-group';coverBox.append(el('h3','Cover'));
    const image=el('img');image.dataset.healthCoverPreview='';image.alt='Cover-Vorschau';image.hidden=true;coverBox.append(image);
    record.Covers?.forEach((cover,index)=>{coverBox.append(el('p',cover.Path+' · '+cover.Width+' × '+cover.Height+' · '+size(cover.Size)+(cover.Valid?'':' · nicht lesbar')));if(cover.Valid)coverBox.append(action('Cover ansehen',()=>send('health-cover-preview',{id:record.Id,index})));});
    const coverStatus=el('p');coverStatus.dataset.healthCoverChoice='';
    const origin=el('select');origin.setAttribute('aria-label','Herkunft des importierten Covers');origin.append(new Option('Manueller Coverimport','Manueller Coverimport'),new Option('KI-generiertes Cover','KI-generiert'));origin.onchange=()=>{coverOrigin=origin.value;};
    const embedLabel=el('label');embedLabel.className='check-line';const embed=el('input');embed.type='checkbox';embed.name='embedCover';embed.dataset.healthEmbedCover='';embed.disabled=!record.Path.toLowerCase().endsWith('.mp3')||(coverBatchIds.length>1&&state.rows.some(row=>coverBatchIds.includes(row.id)&&!row.path.toLowerCase().endsWith('.mp3')));embedLabel.append(embed,document.createTextNode('Gewähltes JPEG zusätzlich verlustfrei in MP3 einbetten'));
    coverBox.append(action('Cover aus vorhandener Quelle / Original-Thumbnail vorbereiten',()=>send('health-cover-recover',{id:record.Id})),action('Eigenes Cover auswählen …',()=>send('health-cover-choose',{id:record.Id})),origin,coverStatus,embedLabel,el('small','Die Quelle wird vor der Übernahme angezeigt. KI-generierte Bilder werden ausdrücklich als solche dokumentiert. Bei mehrteiligen Sets wird das externe Cover gemeinsam im Setordner gespeichert; die MP3-Einbettung erfolgt je ausgewählter Datei. Andere Audioformate werden nicht für neue Covereinbettung verwendet.'));form.append(coverBox);
    const preview=el('button','Reparaturvorschau erstellen');preview.type='submit';preview.className='hot';preview.disabled=state.busy||state.dirty;form.append(preview);
    if(coverBatchIds.length>1)for(const control of scroll.querySelectorAll('input,button'))control.disabled=true;
    form.onsubmit=event=>{event.preventDefault();const Changes={};if(coverBatchIds.length<2)for(const check of form.querySelectorAll('[data-health-field]:checked'))Changes[check.dataset.healthField]=form.elements.namedItem(check.dataset.healthField).value;if(coverBatchIds.length>1&&!coverPath){coverStatus.textContent='Zuerst ein gemeinsames Cover auswählen oder vorbereiten.';return;}const ids=coverBatchIds.length?coverBatchIds:[record.Id];send('health-plan',{requests:ids.map(Id=>({Id,Changes,Json:jsonCheck.checked,CoverPath:coverPath,CoverOrigin:coverOrigin,EmbedCover:embed.checked}))});};
    editor.append(form);if(!editor.open)editor.showModal();
  }
  const planDialog=el('dialog');planDialog.dataset.healthPlanDialog='';planDialog.setAttribute('aria-label','Reparaturvorschau und Freigabe');root.append(planDialog);
  function showPlan(data){
    planToken=data.id;planDialog.replaceChildren(el('h2','Reparaturvorschau'),el('p','Noch keine Musikdatei verändert. '+data.items.length+' Dateien · mindestens '+size(data.bytes)+' für Originalbackups; zusätzlich Platz für temporäre Dateien erforderlich.'));
    for(const item of data.items){const box=el('div');box.className='health-plan-item';box.append(el('strong',item.Path));box.append(el('p',Object.keys(item.Changes||{}).length||item.EmbedCover?'Auswirkung: Musikdatei und Plattenkoffer-Angaben.':'Auswirkung: Plattenkoffer-Angaben'+(item.Cover?' und externe Coverdatei.':'.')+' Audiodatei bleibt unverändert.'));for(const [field,value]of Object.entries(item.Changes||{})){box.append(el('p',(labels[field]||field)+': '+(item.Before?.[field]||'leer')+' → '+(value||'leer')));const evidence=item.Sources?.[field]||[];box.append(el('small',evidence.map(s=>s.Source+': '+s.Value).join(' · ')||'Manuelle Eingabe'));}if(item.Json)box.append(el('p','Fehlende Plattenkoffer-Angaben aus vorhandenen Musikangaben ergänzen.'));if(item.Cover)box.append(el('p','Eigenes JPEG-Cover aus '+item.Cover.Path));if(item.EmbedCover)box.append(el('p','Zusätzlich JPEG in MP3 einbetten · keine Audiokodierung'));if(item.Conflicts?.length)box.append(el('p','Quellenkonflikte: '+item.Conflicts.map(f=>labels[f]||f).join(', ')));planDialog.append(box);}
    const confirm=el('label');confirm.className='check-line';const check=el('input');check.type='checkbox';check.dataset.healthApproveCheck='';confirm.append(check,document.createTextNode('Ich habe Änderungen und Quellen geprüft und gebe genau diesen Reparaturplan frei.'));
    const apply=action('Freigegebene Reparatur ausführen',()=>{if(!check.checked)return;send('health-approve',{token:planToken,approved:true});planDialog.close();editor.close();});apply.className='hot';apply.disabled=true;check.onchange=()=>{apply.disabled=!check.checked;};planDialog.append(confirm,apply,action('Abbrechen',()=>planDialog.close()));if(!planDialog.open)planDialog.showModal();
  }
  const restoreDialog=el('dialog');restoreDialog.dataset.healthRestoreDialog='';restoreDialog.setAttribute('aria-label','Wiederherstellung freigeben');root.append(restoreDialog);
  window.addEventListener('pk-health',({detail:data})=>{
    if(data.type==='health'){state=data;state.rows=state.rows||[];for(const id of selected)if(!state.rows.some(row=>row.id===id))selected.delete(id);render();if(data.mode&&mode!==data.mode)setMode(data.mode);}
    else if(data.type==='health-progress'){if(data.busy!==undefined)state.busy=data.busy;progress(data);}
    else if(data.type==='health-record')openEditor(data.record);
    else if(data.type==='health-plan')showPlan(data);
    else if(data.type==='health-cover'){const image=editor.querySelector('[data-health-cover-preview]');if(image){image.src=data.image;image.hidden=false;}}
    else if(data.type==='health-cover-chosen'){if(data.id&&data.id!==record?.Id)return;coverPath=data.path;editor.querySelector('[data-health-cover-choice]').textContent='Nach Freigabe übernehmen: '+data.path;if(data.image){const image=editor.querySelector('[data-health-cover-preview]');image.src=data.image;image.hidden=false;}}
    else if(data.type==='health-cover-recovered'){coverPath=data.cover.Path;coverOrigin=data.cover.Origin;editor.querySelector('[data-health-cover-choice]').textContent='Vorbereitete Quelle: '+data.cover.Origin+' · '+data.cover.Path+(data.cover.Url?' · '+data.cover.Url:'');if(data.image){const image=editor.querySelector('[data-health-cover-preview]');image.src=data.image;image.hidden=false;}}
    else if(data.type==='health-restore-preview'){
      restoreToken=data.id;restoreDialog.replaceChildren(el('h2','Originale wiederherstellen'),el('p','Backups und Dateizustand wurden geprüft. Folgende Reparaturen werden rückgängig gemacht:'));
      for(const path of data.paths)restoreDialog.append(el('p',path));
      const label=el('label');label.className='check-line';const check=el('input');check.type='checkbox';label.append(check,document.createTextNode('Ich gebe die Wiederherstellung dieser Originale frei.'));
      const apply=action('Originale wiederherstellen',()=>{if(check.checked){send('health-restore-approve',{token:restoreToken,approved:true});restoreDialog.close();}});apply.disabled=true;check.onchange=()=>{apply.disabled=!check.checked;};restoreDialog.append(label,apply,action('Abbrechen',()=>restoreDialog.close()));restoreDialog.showModal();
    }
  });
  setMode('simple');
})();
