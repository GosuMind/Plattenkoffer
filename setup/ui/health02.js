(() => {
  'use strict';
  const root=document.getElementById('pk-concept'),q=s=>root.querySelector(s);
  const send=(command,data={})=>chrome.webview.postMessage({command,...data});
  const el=(tag,text)=>{const node=document.createElement(tag);if(text!==undefined)node.textContent=String(text);return node;};
  const button=(label,fn)=>{const node=el('button',label);node.type='button';node.onclick=fn;return node;};
  const labels={VDJ_METADATA_MISSING:'Datenbank-Tags fehlen',VDJ_METADATA_STALE:'Generischer / ungültiger Datenbankwert',VDJ_METADATA_CONFLICT:'Abweichender vorhandener Wert · manuell prüfen',VDJ_DATABASE_MISSING_ENTRY:'Kein Datenbankeintrag',VDJ_DATABASE_ORPHAN_ENTRY:'Audiodatei nicht vorhanden',VDJ_TAG_COMPATIBILITY_REVIEW:'Kompatibilität manuell prüfen',AUDIO_METADATA_MISSING:'Audio-Tags fehlen oder benötigen Prüfung'};
  let state={},selected=new Set(),selectionIdentity='';
  q('[data-health-vdj-detect]').onclick=()=>send('health-vdj-detect');
  q('[data-health-vdj-use]').onclick=()=>{
    const path=q('[data-health-vdj-candidate]').value;if(!path)return;
    const form=q('[data-health-options]');form.elements.namedItem('VdjDatabase').value=path;form.requestSubmit();
  };
  q('[data-health-vdj-scan]').onclick=()=>send('health-vdj-analyze');
  q('[data-health-vdj-select]').onclick=()=>{for(const row of state.vdj?.Rows||[])if(row.Writable)selected.add(row.Index);renderVdj();};
  q('[data-health-vdj-plan]').onclick=()=>send('health-vdj-plan',{indices:[...selected]});
  q('[data-health-import-legacy]').onclick=()=>send('health-import-reference');
  function metric(container,value,label){const box=el('div');box.className='health-metric';box.append(el('strong',value),el('span',label));container.append(box);}
  function renderVdj(){
    const select=q('[data-health-vdj-candidate]'),old=select.value;select.replaceChildren(new Option('Datenbank selbst auswählen',''));
    for(const candidate of state.candidates||[])select.append(new Option(candidate.Path+' · '+candidate.Version+' · '+candidate.Entries+' Einträge / '+candidate.LibraryMatches+' Bibliothekstreffer',candidate.Path));
    select.value=[...select.options].some(option=>option.value===old)?old:'';
    const report=state.vdj,summary=q('[data-health-vdj-summary]');summary.replaceChildren();
    metric(summary,state.candidates?.length||0,'Erkannte Datenbanken');
    if(report){
      const rows=report.Rows||[];
      for(const [value,label]of [[report.Entries,'Datenbankeinträge'],[rows.filter(r=>r.Audio?.Artist).length,'Zugeordnete Audiodateien'],[rows.filter(r=>r.Changes?.Author).length,'Author ergänzbar'],[rows.filter(r=>r.Changes?.Title).length,'Title ergänzbar'],[rows.filter(r=>r.Codes?.includes('VDJ_METADATA_STALE')).length,'Veraltete / generische Werte'],[rows.filter(r=>r.Codes?.includes('VDJ_DATABASE_ORPHAN_ENTRY')).length,'Verwaiste Einträge'],[rows.filter(r=>r.Codes?.includes('VDJ_DATABASE_MISSING_ENTRY')).length,'Fehlende Datenbankeinträge'],[rows.filter(r=>r.Writable).length,'Reparaturkandidaten']])metric(summary,value,label);
      q('[data-health-vdj-path]').textContent=report.Database+' · Version '+report.Version+' · '+(report.Writable?'DOM-Workaround für 2026 freigegeben':'Nur lesend')+' · Analyse '+new Date(report.ScannedAt).toLocaleString('de-DE');
    }else q('[data-health-vdj-path]').textContent='Gewählte Datenbank: '+(state.options?.VdjDatabase||'Keine. Kandidaten werden nicht automatisch als aktiv ausgewählt.');
    const body=q('[data-health-vdj-rows]');body.replaceChildren();
    for(const row of report?.Rows||[]){
      const tr=el('tr'),check=el('input');check.type='checkbox';check.checked=selected.has(row.Index);check.disabled=!row.Writable||state.busy;check.setAttribute('aria-label',row.Path+' für Datenbankkorrektur auswählen');check.onchange=()=>check.checked?selected.add(row.Index):selected.delete(row.Index);
      const first=el('td');first.append(check);tr.append(first);
      for(const value of [row.Path,row.Audio?.Artist||'–',row.Audio?.Title||'–',row.Current?.Author||'leer',row.Current?.Title||'leer',(row.Codes||[]).map(c=>labels[c]||c).join(' · ')||(row.Writable?'Reparierbar':'Keine Änderung erforderlich')])tr.append(el('td',value));
      body.append(tr);
    }
    q('[data-health-vdj-plan]').disabled=state.busy||!report?.Writable;
    for(const selector of ['[data-health-vdj-detect]','[data-health-vdj-scan]','[data-health-vdj-use]'])q(selector).disabled=!!state.busy;
    const backups=q('[data-health-vdj-backups]');backups.replaceChildren();
    for(const item of state.vdjBackups||[]){const row=el('div',item.path+' · '+item.state+' · '+item.date);row.className='health-history-row';const restore=button('Datenbank-Wiederherstellung prüfen',()=>send('health-vdj-restore-preview',{id:item.id}));restore.disabled=state.busy||item.state==='RESTORED';row.append(restore);backups.append(row);}
    const archives=q('[data-health-quarantine-rows]');archives.replaceChildren();
    for(const item of state.quarantine||[]){const row=el('div',item.path+' · '+item.state+' · Behalten: '+item.keeper);row.className='health-history-row';const restore=button('Wiederherstellung prüfen',()=>send('health-quarantine-restore-preview',{id:item.id}));restore.disabled=state.busy||!['COMMITTED','COMMITTING','ROLLBACK_REQUIRED'].includes(item.state);row.append(restore);archives.append(row);}
    if(!state.quarantine?.length)archives.append(el('p','Noch keine archivierten Dateien. Duplikate in der Scanansicht auswählen und die Archivierung separat freigeben.'));
  }
  const dialog=el('dialog');dialog.dataset.healthSpecialDialog='';dialog.setAttribute('aria-label','Datenbank- oder Quarantänefreigabe');root.append(dialog);
  function showPlan(plan){
    dialog.replaceChildren(el('h2',plan.Type==='VDJ'?'VirtualDJ-Datenbankkorrektur':'Duplikate archivieren'));
    dialog.append(el('p',plan.Type==='VDJ'?'Nur die aufgeführten Author-/Title-Werte werden ergänzt. Vollständige Datenbanksicherung, XML-Inhaltsvergleich und Abschlussprüfung sind verpflichtend. VirtualDJ vollständig schließen.':'Dateien werden nach verifizierter Originalkopie in Quarantäne archiviert. Die angegebene identische Datei bleibt erhalten. PK-Verweise wurden geprüft; unbekannte externe Referenzen müssen manuell geprüft werden.'));
    if(plan.Database)dialog.append(el('p',plan.Database));
    for(const item of plan.Items){
      const box=el('div');box.className='health-plan-item';box.append(el('strong',item.Path));
      if(plan.Type==='VDJ')for(const [key,value]of Object.entries(item.Changes||{}))box.append(el('p',key+': '+(item.Before?.[key]?.Value||'leer')+' → '+value+' · Quelle: aktuelle Audio-Tags'));
      else{box.append(el('p','Behalten: '+item.Keeper),el('p','Original-Dateihash: '+item.Hash));for(const reference of item.References||[])box.append(el('p','Betroffener externer Verweis: '+reference));}
      dialog.append(box);
    }
    const label=el('label');label.className='check-line';const check=el('input');check.type='checkbox';check.dataset.healthSpecialApprove='';label.append(check,document.createTextNode(plan.Type==='VDJ'?'Ich habe die Änderungen geprüft und gebe genau diese Datenbankkorrektur frei.':'Ich habe die Behaltensauswahl sowie externe Referenzen geprüft und gebe die Archivierung frei.'));
    const apply=button('Freigegebenen Auftrag ausführen',()=>{if(check.checked){send('health-special-approve',{token:plan.Id,approved:true,referencesReviewed:plan.Type==='QUARANTINE'});dialog.close();}});apply.disabled=true;check.onchange=()=>{apply.disabled=!check.checked;};dialog.append(label,apply,button('Abbrechen',()=>dialog.close()));dialog.showModal();
  }
  function showRestore(preview){
    dialog.replaceChildren(el('h2','Wiederherstellungsvorschau'),el('p',preview.Path),el('p','Originalhash und aktueller Dateistand wurden geprüft. Vorhandene fremde Änderungen werden nicht überschrieben.'));
    const label=el('label');label.className='check-line';const check=el('input');check.type='checkbox';label.append(check,document.createTextNode('Ich gebe die Wiederherstellung dieses Originals frei.'));
    const apply=button('Original wiederherstellen',()=>{if(check.checked){send('health-special-restore-approve',{token:preview.Id,approved:true});dialog.close();}});apply.disabled=true;check.onchange=()=>{apply.disabled=!check.checked;};dialog.append(label,apply,button('Abbrechen',()=>dialog.close()));dialog.showModal();
  }
  window.addEventListener('pk-health',({detail:data})=>{
    if(data.type==='health'){const identity=(data.vdj?.Database||'')+'|'+(data.vdj?.DatabaseHash||'')+'|'+(data.vdj?.ScannedAt||'');if(identity!==selectionIdentity){selected.clear();selectionIdentity=identity;}state=data;renderVdj();}
    else if(data.type==='health-special-plan')showPlan(data.plan);
    else if(data.type==='health-special-restore')showRestore(data.preview);
    else if(data.type==='health-reference-report')q('[data-health-legacy-report]').textContent=data.text;
  });
})();
