(() => {
  'use strict';
  const root=document.getElementById('pk-concept');
  const q=s=>root.querySelector(s);
  const send=(command,values={})=>window.chrome.webview.postMessage({command,...values});
  const el=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=String(text);return n;};
  const action=(text,fn)=>{const n=el('button',text);n.type='button';n.onclick=fn;return n;};
  const labels={Artist:'Interpret / DJ',Title:'Titel / Setname',Album:'Album',AlbumArtist:'Album-Interpret',Version:'Version / Remix',Label:'Label / Publisher',Genre:'Genre',Year:'Jahr',Date:'Veröffentlichungsdatum',Series:'Set-Reihe',Event:'Veranstaltung',Location:'Location',TrackNumber:'Tracknummer',SourceUrl:'Quell-URL',VideoId:'Video-ID',ISRC:'ISRC'};
  const codeLabels={HEALTHY:'Fehlerfrei, vollständig geprüft',MISSING_ARTIST:'Interpret fehlt',MISSING_TITLE:'Titel fehlt',INVALID_TAG:'Ungültiges Tag',TAG_MISMATCH:'Quellen widersprechen sich',MISSING_JSON:'PK-JSON fehlt',INVALID_JSON:'JSON fehlerhaft',JSON_MISMATCH:'JSON / Tags widersprüchlich',MISSING_COVER:'Cover fehlt',INVALID_COVER:'Cover nicht lesbar',EMBEDDED_COVER_MISSING:'Kein eingebettetes Cover',DUPLICATE_AUDIO:'Identische Datei / Audiodaten',POSSIBLE_DUPLICATE:'Mögliches Duplikat',INVALID_PATH:'Ordnerstruktur prüfen',GENERIC_FILENAME:'Generischer Dateiname (Hinweis)',AUDIO_ERROR:'Audio technisch auffällig',UNSUPPORTED_FORMAT:'Nur lesend unterstützt',MANUAL_REVIEW:'Manuell prüfen'};
  let state={rows:[],backups:[],plans:[],busy:false},tab='overview',page=0,record=null,planToken='',restoreToken='',coverPath='';
  const selected=new Set(),backupSelected=new Set();
  const size=value=>value==null?'–':Number(value)>=1073741824?(Number(value)/1073741824).toFixed(2)+' GB':(Number(value)/1048576).toFixed(1)+' MB';
  const stamp=value=>value?new Date(value).toLocaleString('de-DE'):'Noch kein vollständiger Scan';
  const textCodes=codes=>(codes||[]).map(code=>codeLabels[code]||code).join(' · ');
  const progress=data=>{
    q('[data-health-current]').textContent=data.current||'';
    const p=q('[data-health-progress]');p.hidden=!state.busy;
    p.max=Math.max(1,data.total||1);p.value=data.done||0;
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
    return state.rows.filter(row=>matches(row,q('[data-health-filter]').value)&&[row.path,...Object.values(row.tags||{})].join(' ').toLocaleLowerCase('de').includes(needle));
  }
  function renderRows(){
    const rows=filtered();page=Math.min(page,Math.max(0,Math.ceil(rows.length/100)-1));
    const body=q('[data-health-rows]');body.replaceChildren();
    for(const row of rows.slice(page*100,(page+1)*100)){
      const tr=el('tr');tr.dataset.healthId=row.id;
      const check=el('input');check.type='checkbox';check.checked=selected.has(row.id);check.setAttribute('aria-label',(row.tags?.Title||row.path)+' auswählen');
      check.onchange=()=>{check.checked?selected.add(row.id):selected.delete(row.id);updateSelection();};tr.append(el('td'));tr.lastChild.append(check);
      for(const field of ['Artist','Title','Version','Album','Genre','Year'])tr.append(el('td',row.tags?.[field]||'–'));
      const duration=row.duration?Math.floor(row.duration/60)+':'+String(Math.floor(row.duration%60)).padStart(2,'0'):'–';
      for(const value of [row.codec?row.path.split('.').at(-1).toUpperCase()+' / '+row.codec:'–',row.bitrate?Math.round(Number(row.bitrate)/1000)+' kbit/s':'–',duration,row.rate?(Number(row.rate)/1000)+' kHz / '+row.channels:'–',size(row.size),row.coverCount+' extern'+(row.embeddedCover?' + eingebettet':''),textCodes(row.codes),row.integrity==='DECODE_CHECKED'?'Vollständig dekodiert':row.integrity==='PACKETS_CHECKED'?'Pakete geprüft · kein Tiefenscan':row.integrity,row.path])tr.append(el('td',value));
      const cell=el('td');cell.append(action(row.repairable?'Prüfen / bearbeiten':'Lesend prüfen',()=>send('health-record',{id:row.id})));tr.append(cell);body.append(tr);
    }
    q('[data-health-page]').textContent=rows.length+' Dateien · Seite '+(page+1)+' / '+Math.max(1,Math.ceil(rows.length/100));
    q('[data-health-prev]').disabled=!page;q('[data-health-next]').disabled=(page+1)*100>=rows.length;
    updateSelection();
  }
  function updateSelection(){
    q('[data-health-selected]').textContent=selected.size+' ausgewählt';
    for(const selector of ['[data-health-batch]','[data-health-json]'])q(selector).disabled=state.busy||!selected.size||state.dirty;
  }
  function render(){
    q('[data-health-status]').textContent=state.status||'';
    for(const control of root.querySelectorAll('[data-health-full],[data-health-incremental],[data-health-options] input,[data-health-options] button'))control.disabled=state.busy;
    q('[data-health-cancel]').disabled=!state.busy;
    progress(state.progress||{});
    const form=q('[data-health-options]');
    for(const [key,value]of Object.entries(state.options||{}))if(form.elements.namedItem(key))form.elements.namedItem(key).value=Array.isArray(value)?value.join(', '):value;
    const metrics=q('[data-health-summary]');metrics.replaceChildren();
    const entries=[['Files','Audiodateien'],['Tracks','Tracks'],['Sets','DJ-Sets'],['Healthy','Fehlerfrei · tiefengeprüft'],['NeedsReview','Mit Hinweisen / Prüfbedarf'],['AudioErrors','Technisch auffällig'],['MissingTags','Fehlende Audio-Tags'],['MissingJson','Fehlendes PK-JSON'],['MissingCovers','Fehlende Cover'],['Conflicts','Metadatenkonflikte'],['Duplicates','Duplikatverdacht']];
    for(const [key,label]of entries){const box=el('div');box.className='health-metric';box.append(el('strong',state.summary?state.summary[key]:'–'),el('span',label));metrics.append(box);}
    const bytes=el('div');bytes.className='health-metric';bytes.append(el('strong',state.summary?size(state.summary.Bytes):'–'),el('span','Speicherverbrauch'));metrics.append(bytes);
    q('[data-health-score]').textContent=state.summary?(state.summary.Score==null?'Noch kein Health Score. Dafür ist ein vollständiger Tiefenscan nötig.':'Health Score '+state.summary.Score+' % · '+state.summary.Healthy+' / '+state.summary.FullyChecked+' vollständig dekodierte Dateien ohne offene Prüfhinweise.')+' Letzter Scan: '+stamp(state.lastScan)+' · '+state.scanState:'';
    q('[data-health-warning]').textContent=[...(state.warnings||[]),state.dirty?'Die angezeigten Scanwerte stammen von vor den Änderungen. Bitte neu scannen.':''].filter(Boolean).join(' ');
    renderRows();renderHistory();
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
    for(const button of root.querySelectorAll('[data-health-tab]'))button.setAttribute('aria-pressed',String(button.dataset.healthTab===tab));
    const sections={'[data-health-history]':'repairs','[data-health-backups]':'backups','[data-health-reports]':'reports','[data-health-vdj]':'vdj','[data-health-quality-note]':'quality'};
    for(const [selector,name]of Object.entries(sections))q(selector).hidden=tab!==name;
    q('[data-health-library]').hidden=['repairs','backups','reports'].includes(tab);
    q('[data-health-filter]').value=({metadata:'missing',covers:'MISSING_COVER',integrity:'AUDIO_ERROR',duplicates:'duplicates',paths:'INVALID_PATH',vdj:'vdj'})[tab]||'all';
    page=0;renderRows();
  };
  for(const button of root.querySelectorAll('[data-health-tab]'))button.onclick=()=>setTab(button.dataset.healthTab);
  q('[data-health-search]').oninput=()=>{page=0;renderRows();};q('[data-health-filter]').onchange=()=>{page=0;renderRows();};
  q('[data-health-prev]').onclick=()=>{page--;renderRows();};q('[data-health-next]').onclick=()=>{page++;renderRows();};
  q('[data-health-select]').onclick=()=>{filtered().forEach(row=>selected.add(row.id));renderRows();};
  q('[data-health-clear]').onclick=()=>{selected.clear();renderRows();};
  q('[data-health-full]').onclick=()=>send('health-scan',{deep:q('[data-health-deep]').checked,incremental:false});
  q('[data-health-incremental]').onclick=()=>send('health-scan',{deep:q('[data-health-deep]').checked,incremental:true});
  q('[data-health-cancel]').onclick=()=>send('health-cancel');
  q('[data-health-options]').onsubmit=event=>{event.preventDefault();send('health-options',{values:Object.fromEntries(new FormData(event.target))});};
  q('[data-health-batch]').onclick=()=>send('health-plan',{requests:[...selected].map(Id=>({Id}))});
  q('[data-health-json]').onclick=()=>send('health-plan',{requests:[...selected].map(Id=>({Id,Json:true}))});
  q('[data-health-export]').onclick=()=>send('health-export');q('[data-health-open-reports]').onclick=()=>send('health-reports');
  q('[data-health-export-repairs]').onclick=()=>send('health-export-repairs');
  q('[data-health-restore]').onclick=()=>send('health-restore-preview',{ids:[...backupSelected]});
  const editor=el('dialog');editor.dataset.healthEditor='';editor.setAttribute('aria-label','Metadaten und Quellen vergleichen');root.append(editor);
  function openEditor(value){
    record=value;coverPath='';editor.replaceChildren();
    const header=el('header');header.append(el('h2','Metadaten und Quellen'),action('Schließen',()=>editor.close()));editor.append(header,el('p',record.Path),el('p',textCodes(record.Codes)));
    if(record.Notes?.length)editor.append(el('p',record.Notes.join(' ')));
    if(!record.Resolved){editor.append(el('p','Keine belastbare Metadatenanalyse verfügbar.'));editor.showModal();return;}
    const form=el('form');form.dataset.healthEditorForm='';
    const scroll=el('div');scroll.className='health-editor-fields';const table=el('table');
    const headings=table.createTHead().insertRow();for(const text of ['Ändern','Feld','Audio-Tag','PK-JSON / Quellen','Neuer Wert'])headings.append(el('th',text));
    const body=table.createTBody();
    for(const [field,label]of Object.entries(labels)){
      const row=body.insertRow();const check=el('input');check.type='checkbox';check.dataset.healthField=field;check.setAttribute('aria-label',label+' ändern');check.disabled=!record.Repairable;row.insertCell().append(check);row.insertCell().textContent=label;row.insertCell().textContent=record.Tags?.[field]||'–';
      const sources=row.insertCell();sources.append(el('small','PK: '+(record.Pk?.[field]||'–')));
      const input=el('input');input.name=field;input.value=record.Resolved.Values?.[field]||record.Tags?.[field]||'';input.disabled=!record.Repairable;input.maxLength=2000;input.setAttribute('aria-label',label+' neuer Wert');
      if(record.Resolved.Conflicts?.includes(field))sources.append(el('small','KONFLIKT · Wert ausdrücklich auswählen'));
      for(const source of record.Resolved.Evidence?.[field]||[]){const choose=action(source.Source+': '+source.Value+' · '+source.Confidence,()=>{input.value=source.Value;check.checked=true;});choose.disabled=!record.Repairable;sources.append(choose);}
      input.oninput=()=>{check.checked=true;};row.insertCell().append(input);
      if(!record.Tags?.[field]&&input.value&&!record.Resolved.Conflicts?.includes(field)&&['Artist','Title'].includes(field))check.checked=record.Repairable;
    }
    scroll.append(table);form.append(scroll);
    const json=el('label');json.className='check-line';const jsonCheck=el('input');jsonCheck.type='checkbox';jsonCheck.name='rebuildJson';jsonCheck.checked=record.Codes.includes('MISSING_JSON');json.append(jsonCheck,document.createTextNode('PK-JSON aus vorhandenen Tags ergänzen; unbekannte Felder erhalten'));form.append(json);
    const coverBox=el('section');coverBox.className='settings-group';coverBox.append(el('h3','Cover'));
    const image=el('img');image.dataset.healthCoverPreview='';image.alt='Cover-Vorschau';image.hidden=true;coverBox.append(image);
    record.Covers?.forEach((cover,index)=>{coverBox.append(el('p',cover.Path+' · '+cover.Width+' × '+cover.Height+' · '+size(cover.Size)+(cover.Valid?'':' · nicht lesbar')));if(cover.Valid)coverBox.append(action('Cover ansehen',()=>send('health-cover-preview',{id:record.Id,index})));});
    const coverStatus=el('p');coverStatus.dataset.healthCoverChoice='';coverBox.append(action('Eigenes Cover auswählen …',()=>send('health-cover-choose')),coverStatus,el('small','Ein gewähltes Bild wird nach Freigabe als eigenes JPEG-Cover gespeichert. Vorhandene Cover bleiben erhalten. Audio-Cover werden im MVP nicht neu eingebettet.'));form.append(coverBox);
    const preview=el('button','Reparaturvorschau erstellen');preview.type='submit';preview.className='hot';preview.disabled=state.busy||state.dirty;form.append(preview);
    form.onsubmit=event=>{event.preventDefault();const Changes={};for(const check of form.querySelectorAll('[data-health-field]:checked'))Changes[check.dataset.healthField]=form.elements.namedItem(check.dataset.healthField).value;send('health-plan',{requests:[{Id:record.Id,Changes,Json:jsonCheck.checked,CoverPath:coverPath}]});};
    editor.append(form);if(!editor.open)editor.showModal();
  }
  const planDialog=el('dialog');planDialog.dataset.healthPlanDialog='';planDialog.setAttribute('aria-label','Reparaturvorschau und Freigabe');root.append(planDialog);
  function showPlan(data){
    planToken=data.id;planDialog.replaceChildren(el('h2','Reparaturvorschau'),el('p','Noch keine Musikdatei verändert. '+data.items.length+' Dateien · mindestens '+size(data.bytes)+' für Originalbackups; zusätzlich Platz für temporäre Dateien erforderlich.'));
    for(const item of data.items){const box=el('div');box.className='health-plan-item';box.append(el('strong',item.Path));for(const [field,value]of Object.entries(item.Changes||{})){box.append(el('p',(labels[field]||field)+': '+(item.Before?.[field]||'leer')+' → '+(value||'leer')));const evidence=item.Sources?.[field]||[];box.append(el('small',evidence.map(s=>s.Source+': '+s.Value).join(' · ')||'Manuelle Eingabe'));}if(item.Json)box.append(el('p','PK-JSON aus vorhandenen Tags ergänzen.'));if(item.Cover)box.append(el('p','Eigenes JPEG-Cover aus '+item.Cover.Path));if(item.Conflicts?.length)box.append(el('p','Quellenkonflikte: '+item.Conflicts.map(f=>labels[f]||f).join(', ')));planDialog.append(box);}
    const confirm=el('label');confirm.className='check-line';const check=el('input');check.type='checkbox';check.dataset.healthApproveCheck='';confirm.append(check,document.createTextNode('Ich habe Änderungen und Quellen geprüft und gebe genau diesen Reparaturplan frei.'));
    const apply=action('Freigegebene Reparatur ausführen',()=>{if(!check.checked)return;send('health-approve',{token:planToken,approved:true});planDialog.close();editor.close();});apply.className='hot';apply.disabled=true;check.onchange=()=>{apply.disabled=!check.checked;};planDialog.append(confirm,apply,action('Abbrechen',()=>planDialog.close()));if(!planDialog.open)planDialog.showModal();
  }
  const restoreDialog=el('dialog');restoreDialog.dataset.healthRestoreDialog='';restoreDialog.setAttribute('aria-label','Wiederherstellung freigeben');root.append(restoreDialog);
  window.addEventListener('pk-health',({detail:data})=>{
    if(data.type==='health'){state=data;for(const id of selected)if(!state.rows.some(row=>row.id===id))selected.delete(id);render();}
    else if(data.type==='health-progress')progress(data);
    else if(data.type==='health-record')openEditor(data.record);
    else if(data.type==='health-plan')showPlan(data);
    else if(data.type==='health-cover'){const image=editor.querySelector('[data-health-cover-preview]');if(image){image.src=data.image;image.hidden=false;}}
    else if(data.type==='health-cover-chosen'){coverPath=data.path;editor.querySelector('[data-health-cover-choice]').textContent='Nach Freigabe übernehmen: '+data.path;}
    else if(data.type==='health-restore-preview'){
      restoreToken=data.id;restoreDialog.replaceChildren(el('h2','Originale wiederherstellen'),el('p','Backups und Dateizustand wurden geprüft. Folgende Reparaturen werden rückgängig gemacht:'));
      for(const path of data.paths)restoreDialog.append(el('p',path));
      const label=el('label');label.className='check-line';const check=el('input');check.type='checkbox';label.append(check,document.createTextNode('Ich gebe die Wiederherstellung dieser Originale frei.'));
      const apply=action('Originale wiederherstellen',()=>{if(check.checked){send('health-restore-approve',{token:restoreToken,approved:true});restoreDialog.close();}});apply.disabled=true;check.onchange=()=>{apply.disabled=!check.checked;};restoreDialog.append(label,apply,action('Abbrechen',()=>restoreDialog.close()));restoreDialog.showModal();
    }
  });
})();
