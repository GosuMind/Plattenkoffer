(() => {
  const bridge = window.chrome.webview;
  const root = document.getElementById("pk-concept");
  const query = selector => root.querySelector(selector);
  const schemas = {
    "": {artist:"Künstler / DJ",year:"Jahr",genre:"Genre",kind:"Typ"},
    Track: {artist:"Künstler",album:"Album",year:"Jahr",label:"Label",version:"Version / Remix",genre:"Genre"},
    Set: {artist:"DJ",date:"Aufnahmedatum",year:"Jahr",series:"Set-Reihe",event:"Veranstaltung",place:"Location",genre:"Genre"}
  };
  const search = query("input[type=search]");
  const results = query("[data-results]");
  const detail = query("[data-detail]");
  const player = query("[data-toggle]");
  const seek = query("footer input");
  const dialog = query("[data-import-dialog]");
  const help = query("[data-help-dialog]");
  const restore = query("[data-restore-dialog]");
  const settingsForm = query("[data-settings-form]");
  const convertForm = query("[data-convert-form]");
  const convertNav = document.createElement("button");
  convertNav.textContent = "Umwandeln";
  convertNav.dataset.command = "convert";
  query('nav [data-command="settings"]').before(convertNav);
  const healthNav=document.createElement('button');healthNav.textContent='Bibliothekspflege';healthNav.dataset.command='health';
  query('nav [data-command="settings"]').before(healthNav);
  const syncConvertFormat = () => {
    const format = convertForm.elements.namedItem("format").value;
    const lossy = ["MP3","M4A (AAC)","Opus","OGG (Vorbis)"].includes(format);
    query("[data-convert-bitrate]").hidden = !lossy;
    convertForm.elements.namedItem("bitrate").disabled = !lossy;
    const rate = convertForm.elements.namedItem("rate");
    for (const option of rate.options) {
      option.disabled = format === "Opus" ? !!option.value && option.value !== "48000" : format === "MP3" && option.value === "96000";
    }
    if (rate.selectedOptions[0]?.disabled) rate.value = "";
  };
  convertForm.elements.namedItem("format").onchange = syncConvertFormat;
  syncConvertFormat();
  const entryDialog = query("[data-entry-dialog]");
  const entryForm = query("[data-entry-form]");
  let entryAction = "", entryId = "", exporting = false;
  let previewRevision = 0, previewTimer;
  const namePreview = query("[data-set-name-preview]");
  function refreshSetNamePreview() {
    clearTimeout(previewTimer);
    const revision = ++previewRevision;
    const isSet = entryAction === "edit" && entryForm.elements.namedItem("Type")?.value === "Sets";
    namePreview.hidden = !isSet;
    if (isSet) previewTimer = setTimeout(() => {
      if (!entryDialog.open) return;
      send("set-name-preview",{id:entryId,revision,values:Object.fromEntries(new FormData(entryForm))});
    }, 150);
  }
  let collection = [], view = "cover", kind = "", selected = null;
  let favoritesOnly = false, playlists = [], activePlaylist = "";
  let preferences = {TileSize:180,Accent:"Rost",Density:"Normal",FontScale:100,ShowDetails:true,DefaultView:"auto",Sort:"artist",StartVolume:80,ResumeSets:true,AutoNext:false,Shuffle:false,Repeat:"off",MiniTopMost:true};
  let preferenceTimer;
  const checkedIds = new Set();
  let visibleEntries = [], lastTitleClick = {id:null,time:0};
  const audioInfo = new Map();
  try { if (localStorage.getItem("library-view") === "list") view = "list"; } catch {}
  let seeking = false, page = "collection", sourceMode = "query";
  let playback = { id:null, active:false, playing:false }, visibleSelection = null;
  let tracklistEntry = null;
  let coverEntry = null;
  const coverDialog = query("[data-cover-dialog]");
  function openCoverEditor(entry) {
    coverEntry = entry;
    const preview = query("[data-cover-preview]");
    preview.hidden = !entry.cover;
    if (entry.cover) preview.src = entry.cover;
    query("[data-cover-save]").disabled = true;
    query("[data-cover-reset]").hidden = true;
    query("[data-cover-status]").textContent = "";
    coverDialog.showModal();
    send("cover-edit",{id:entry.id});
  }
  query("[data-cover-close]").onclick = () => coverDialog.close();
  for (const action of ["choose","save","reset"]) {
    query("[data-cover-" + action + "]").onclick = () => send("cover-" + action,{id:coverEntry.id});
  }
  const tracklist = query("[data-tracklist-dialog]");
  const tracklistAdd = query("[data-tracklist-add]");
  const tracklistImport = query("[data-tracklist-import]");
  const tracklistStatus = query("[data-tracklist-status]");
  const scan = query("[data-tracklist-scan]");
  const scanReview = query("[data-scan-review]");
  const scanRows = query("[data-scan-rows]");
  const scanStatus = query("[data-scan-status]");
  const scans = new Map();
  let confirmingScan = false;
  const formatStamp = seconds => String(Math.floor(seconds/60)).padStart(2,"0") + ":" + String(seconds%60).padStart(2,"0");
  function parseStamp(value) {
    const text = value.trim();
    if (!/^\d{1,5}:[0-5]\d(?::[0-5]\d)?$/.test(text)) return null;
    return text.split(":").reduce((total,part) => total*60 + Number(part),0);
  }
  function updateScanRanges() {
    const rows = [...scanRows.children];
    rows.forEach((row,index) => {
      const current = parseStamp(row.querySelector("[data-stamp]").value);
      const next = index + 1 < rows.length
        ? parseStamp(rows[index+1].querySelector("[data-stamp]").value) : scans.get(tracklistEntry.id)?.duration;
      row.querySelector("small").textContent = current !== null && next > current
        ? formatStamp(current) + "–" + formatStamp(next) : "";
    });
  }
  function appendScanRow(item) {
    const row = element("div");
    const input = (label,value,length) => {
      const control = element("input");
      control.setAttribute("aria-label",label);
      control.placeholder = label;
      control.value = value;
      control.maxLength = length;
      return control;
    };
    const stamp = input("MM:SS",item.second === null ? "" : formatStamp(item.second),12);
    stamp.dataset.stamp = "";
    stamp.oninput = updateScanRanges;
    row.append(stamp,input("Interpret",item.artist,300),input("Tracktitel",item.title,300),
      button("Vorhören",() => {
        const second = parseStamp(stamp.value);
        if (second === null || second >= scans.get(tracklistEntry.id)?.duration) {
          scanStatus.textContent = "Bitte einen gültigen Timecode im Set angeben.";stamp.focus();return;
        }
        send("tracklist-preview",{id:tracklistEntry.id,second});
      }),iconAction("×","Vorschlag entfernen",() => {row.remove();updateScanRanges();}),element("small"));
    const data = scans.get(tracklistEntry.id);
    if (data?.points?.length && data.rows.some(item => item.second === null)) {
      const choices = element("select");
      choices.setAttribute("aria-label","Startzeit aus dem Scan wählen");
      choices.append(new Option("Zeitvorschlag wählen", ""));
      for (const second of data.points) {
        choices.append(new Option(formatStamp(second), String(second)));
      }
      choices.onchange = () => {
        if (!choices.value) return;
        stamp.value = formatStamp(Number(choices.value));
        choices.value = "";
        updateScanRanges();
      };
      row.append(choices);
    }
    scanRows.append(row);
  }
  function showScan(data) {
    scan.querySelector("button").disabled = !!data?.busy;
    scanStatus.textContent = data?.status || "";
    scanReview.hidden = !data?.rows;
    scanRows.replaceChildren();
    if (data?.rows) {
      data.rows.forEach(appendScanRow);
      updateScanRanges();
    }
  }
  scan.onsubmit = event => {
    event.preventDefault();
    scan.querySelector("button").disabled = true;
    send("tracklist-scan",{id:tracklistEntry.id,text:scan.elements.namedItem("text").value});
  };
  query("[data-scan-add]").onclick = () => appendScanRow({second:null,artist:"",title:""});
  scanReview.onsubmit = event => {
    event.preventDefault();
    const rows = [];
    let previous = -1;
    for (const row of scanRows.children) {
      const [stamp,artist,title] = row.querySelectorAll("input");
      const second = parseStamp(stamp.value);
      if ((stamp.value.trim() && second === null) ||
          (second !== null && (second <= previous || second >= scans.get(tracklistEntry.id)?.duration))) {
        scanStatus.textContent = "Eingetragene Zeiten müssen gültig sein und aufsteigen. Leere Zeiten sind erlaubt.";
        stamp.focus();
        return;
      }
      if (second !== null) previous = second;
      if (second !== null || artist.value.trim() || title.value.trim()) {
        rows.push({second,artist:artist.value,title:title.value});
      }
    }
    if (!rows.length) return;
    confirmingScan = true;
    send("tracklist-confirm",{id:tracklistEntry.id,rows});
  };
  function updateTracklistPlayer() {
    tracklistAdd.querySelector("button").disabled = !playback.active || playback.id !== tracklistEntry?.id;
  }
  function openTracklist(entry) {
    tracklistEntry = entry;
    tracklistAdd.reset();
    tracklistImport.reset();
    scan.reset();
    confirmingScan = false;
    showScan(scans.get(entry.id));
    query("[data-tracklist-rows]").replaceChildren();
    query("[data-tracklist-title]").textContent = entry.title;
    query("[data-tracklist-description]").hidden = !entry.hasDescription;
    tracklistStatus.textContent = "";
    updateTracklistPlayer();
    tracklist.showModal();
    send("tracklist-open",{id:entry.id});
  }
  function renderTracklist(data) {
    if (!tracklist.open || data.id !== tracklistEntry?.id) return;
    tracklistStatus.textContent = data.status || "";
    scan.querySelector("button").disabled = !!scans.get(data.id)?.busy;
    if (confirmingScan) {
      confirmingScan = false;
      scanStatus.textContent = data.status || "";
      if (data.rows) { scanReview.hidden = true; scans.delete(data.id); }
    }
    if (!data.rows) return;
    const box = query("[data-tracklist-rows]");
    box.replaceChildren();
    if (!data.rows.length) { box.textContent = "Noch keine Tracks eingetragen."; return; }
    const table = element("table");
    const header = table.createTHead().insertRow();
    for (const caption of ["Ab","Interpret","Track",""]) header.append(element("th",caption));
    const body = table.createTBody();
    data.rows.forEach((item,index) => {
      const row = body.insertRow();
      const timeCell = row.insertCell();
      if (item.second == null) {
        timeCell.textContent = "Ohne Timecode";
      } else {
        timeCell.append(button(formatStamp(item.second),() => {
          send("tracklist-jump",{id:data.id,index});
        }));
      }
      timeCell.append(button(item.second == null ? "Zeit ergänzen" : "Zeit ändern", event => {
        event.currentTarget.hidden = true;
        const form = element("form");
        const input = element("input");
        input.setAttribute("aria-label","Timecode (MM:SS oder HH:MM:SS)");
        input.placeholder = "MM:SS";
        input.value = item.second == null ? "" : formatStamp(item.second);
        const save = element("button","Speichern");
        save.type = "submit";
        form.append(input,save);
        form.onsubmit = submit => {
          submit.preventDefault();
          const second = parseStamp(input.value);
          if (input.value.trim() && second === null) {
            tracklistStatus.textContent = "Gib eine Zeit im Format MM:SS oder HH:MM:SS ein.";
            return;
          }
          send("tracklist-time",{id:data.id,index,second});
        };
        timeCell.append(form);
        input.focus();
      }));
      row.insertCell().textContent = item.artist || "–";
      row.insertCell().textContent = item.title;
      row.insertCell().append(iconAction("×","Eintrag entfernen",() => send("tracklist-remove",{id:data.id,index})));
    });
    box.append(table);
  }
  query("[data-tracklist-close]").onclick = () => tracklist.close();
  query("[data-tracklist-description]").onclick = () => send("tracklist-description",{id:tracklistEntry.id});
  tracklistAdd.onsubmit = event => {
    event.preventDefault();
    send("tracklist-add",{id:tracklistEntry.id,...Object.fromEntries(new FormData(tracklistAdd))});
  };
  tracklistImport.onsubmit = event => {
    event.preventDefault();
    send("tracklist-import",{id:tracklistEntry.id,text:tracklistImport.elements.namedItem("text").value});
  };
  const importForm = query("[data-youtube]");
  query("[data-help]").onclick = () => help.showModal();
  query("[data-restore]").onclick = () => restore.showModal();
  function showPage(next) {
    if (page === "downloads" && next !== page) send("refresh");
    page = next;
    for (const name of ["collection","downloads","settings","diagnostics","convert","health"]) {
      query("[data-" + name + "]").hidden = name !== page;
    }
    updateNavigation();
  }
  function showDownloads(mode) {
    showPage("downloads");
    if (mode) sourceMode = mode;
    const queryMode = sourceMode === "query";
    query("[data-query-label]").hidden = !queryMode;
    query("[data-links-label]").hidden = queryMode;
    query("[data-preview]").textContent = queryMode ? "Auf YouTube suchen" : "Vorschau laden";
    query("[data-switch]").textContent = queryMode ? "YouTube-Links eingeben" : "Zur YouTube-Suche";
    importForm.elements.namedItem(sourceMode).focus();
  }
  function showCollection() {
    showPage("collection");
  }
  function updateNavigation() {
    for (const control of root.querySelectorAll("[data-kind]")) {
      control.setAttribute("aria-pressed", String(page === "collection" && !favoritesOnly && !activePlaylist && control.dataset.kind === kind));
    }
    for (const name of ["downloads","settings","convert","health"]) {
      query('nav [data-command="' + name + '"]').setAttribute("aria-pressed", String(page === name));
    }
    query("[data-help]").setAttribute("aria-pressed", String(page === "diagnostics"));
    query("[data-favorites]").setAttribute("aria-pressed",String(page === "collection" && favoritesOnly));
    query("[data-exit-favorites]").hidden = !favoritesOnly;
  }
  const send = (command, data = {}) => bridge.postMessage({command, ...data});
  const element = (tag, value) => {
    const node = document.createElement(tag);
    if (value !== undefined) node.textContent = value;
    return node;
  };
  const button = (caption, invoke) => {
    const node = element("button", caption);
    node.type = "button";
    node.addEventListener("click", invoke);
    return node;
  };
  function playEntry(entry, fromStart = false) {
    send("play",{id:entry.id,fromStart,playlistId:activePlaylist,ids:preferences.AutoNext && !activePlaylist ? visibleEntries.map(item => item.id) : []});
  }
  function favoriteButton(entry) {
    const control = iconAction(entry.favorite ? "♥" : "♡",entry.favorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen",() => {
      lastTitleClick = {id:null,time:0};
      send("favorite",{id:entry.id,value:!entry.favorite});
    });
    control.classList.add("favorite-button");
    control.setAttribute("aria-pressed",String(!!entry.favorite));
    return control;
  }
  function applyPreferences(next) {
    const previous = preferences;
    preferences = {...preferences,...next};
    root.style.setProperty("--tile-size",preferences.TileSize + "px");
    root.style.setProperty("--font-scale",preferences.FontScale / 100);
    root.dataset.accent = preferences.Accent;
    root.dataset.density = preferences.Density;
    root.dataset.details = String(preferences.ShowDetails);
    query("[data-tile-size]").value = preferences.TileSize;
    for (const [name,value] of Object.entries(preferences)) {
      const control = settingsForm.elements.namedItem(name);
      if (!control) continue;
      if (control.type === "checkbox") control.checked = value;
      else control.value = value;
    }
    if (preferences.DefaultView !== "auto" && preferences.DefaultView !== previous.DefaultView) view = preferences.DefaultView;
    if (preferences.StartVolume !== previous.StartVolume) query("[data-volume]").value = preferences.StartVolume;
    render();
  }
  query("[data-tile-size]").oninput = event => {
    const TileSize = Number(event.target.value);
    applyPreferences({TileSize});
    clearTimeout(preferenceTimer);
    preferenceTimer = setTimeout(() => send("preferences-change",{values:{TileSize}}),250);
  };
  query("[data-favorites]").onclick = () => {
    favoritesOnly = true; activePlaylist = ""; kind = "";
    query("[data-active-playlist]").value = "";
    createFilters(); showCollection(); render();
  };
  query("[data-exit-favorites]").onclick = () => { favoritesOnly = false; render(); };
  const playlistManager = query("[data-playlists-dialog]");
  const playlistManagerForm = query("[data-playlist-manager]");
  const playlistSelect = query("[data-playlist-select]");
  let playlistEntryIds = null;
  let newPlaylistName = "";
  function renderPlaylists() {
    const chosen = playlistSelect.value;
    playlistSelect.replaceChildren(...playlists.map(list => new Option(list.name,list.id)));
    playlistSelect.value = playlists.some(list => list.id === chosen) ? chosen : playlists[0]?.id || "";
    const list = playlists.find(item => item.id === playlistSelect.value);
    playlistManagerForm.elements.listName.value = list?.name || "";
    query("[data-playlist-items]").replaceChildren(...(list?.items || []).map((item,index) => {
      const row = element("li");
      row.append(element("span",item.title + (item.missing ? " · nicht in der Sammlung" : "")));
      for (const [symbol,direction] of [["↑",-1],["↓",1]]) {
        const move = iconAction(symbol,direction === -1 ? "Nach oben" : "Nach unten",() => send("playlist-order",{playlistId:list.id,index,direction}));
        move.disabled = direction === -1 ? index === 0 : index === list.items.length - 1;
        row.append(move);
      }
      row.append(iconAction("×","Aus Playlist entfernen",() => send("playlist-remove",{playlistId:list.id,index})));
      return row;
    }));
    for (const name of ["rename","delete","add","play","show"]) query("[data-playlist-" + name + "]").disabled = !list;
    query("[data-playlist-add]").disabled = !list || !(playlistEntryIds?.length || checkedIds.size);
    const picker = query("[data-active-playlist]");
    picker.replaceChildren(new Option("Alle Titel",""),...playlists.map(item => new Option(item.name,item.id)));
    if (!playlists.some(item => item.id === activePlaylist)) activePlaylist = "";
    picker.value = activePlaylist;
    query("[data-play-active-list]").disabled = !activePlaylist || !playlists.find(item => item.id === activePlaylist)?.items.some(item => !item.missing);
  }
  function openPlaylists(ids = null) {
    playlistEntryIds = ids;
    renderPlaylists();
    query("[data-playlist-status]").textContent = "";
    if (!playlistManager.open) playlistManager.showModal();
  }
  query("[data-open-playlists]").onclick = () => openPlaylists();
  query("[data-close-playlists]").onclick = () => playlistManager.close();
  playlistManagerForm.onsubmit = event => event.preventDefault();
  playlistSelect.onchange = renderPlaylists;
  query("[data-selection-playlist]").onclick = () => openPlaylists([...checkedIds]);
  query("[data-playlist-create]").onclick = () => {
    const name = playlistManagerForm.elements.newName.value.trim();
    if (name) { newPlaylistName = name; send("playlist-create",{name}); playlistManagerForm.elements.newName.value = ""; }
  };
  query("[data-playlist-rename]").onclick = () => send("playlist-rename",{playlistId:playlistSelect.value,name:playlistManagerForm.elements.listName.value.trim()});
  query("[data-playlist-delete]").onclick = () => send("playlist-delete",{playlistId:playlistSelect.value});
  query("[data-playlist-add]").onclick = () => send("playlist-add",{playlistId:playlistSelect.value,ids:playlistEntryIds || [...checkedIds]});
  query("[data-playlist-play]").onclick = () => send("playlist-play",{playlistId:playlistSelect.value});
  query("[data-play-active-list]").onclick = () => send("playlist-play",{playlistId:activePlaylist});
  function showPlaylist(id) {
    activePlaylist = id; favoritesOnly = false; kind = "";
    createFilters(); showCollection(); renderPlaylists(); render();
  }
  query("[data-playlist-show]").onclick = () => { showPlaylist(playlistSelect.value); playlistManager.close(); };
  query("[data-active-playlist]").onchange = event => showPlaylist(event.target.value);
  const metadataDialog = query("[data-metadata-dialog]");
  const metadataSearch = query("[data-metadata-search]");
  const metadataApply = query("[data-metadata-apply]");
  const metadataLabels = {Album:"Album",Year:"Jahr",Label:"Label",Version:"Version / Remix",Genre:"Genre"};
  let metadataEntry = null, metadataKey = "", metadataBusy = false;
  let metadataQueue = [], metadataIndex = 0, metadataSaved = 0, metadataSkipped = 0;
  function updateMetadataSave() {
    query("[data-metadata-save]").disabled = metadataBusy || !metadataKey ||
      !metadataApply.querySelector('input[type="checkbox"]:checked');
  }
  function openMetadata(entry, fromBatch = false) {
    if (!fromBatch) metadataQueue = [];
    metadataEntry = entry;
    metadataKey = "";
    metadataBusy = false;
    metadataSearch.elements.artist.value = entry.artist || "";
    metadataSearch.elements.title.value = entry.originalTitle || entry.title;
    query("[data-metadata-results]").replaceChildren();
    query("[data-metadata-status]").textContent = "";
    metadataApply.hidden = true;
    metadataSearch.querySelectorAll("input,button").forEach(control => control.disabled = false);
    query("[data-metadata-next]").hidden = !metadataQueue.length;
    query("[data-metadata-next]").disabled = false;
    const progress = query("[data-metadata-progress]");
    progress.hidden = !metadataQueue.length;
    progress.textContent = metadataQueue.length ? `Track ${metadataIndex + 1} von ${metadataQueue.length} · ${entry.title}` : "";
    if (!metadataDialog.open) metadataDialog.showModal();
    send("metadata-open",{id:entry.id});
  }
  query("[data-close-metadata]").onclick = () => metadataDialog.close();
  metadataDialog.addEventListener("close",() => { metadataQueue = []; });
  function advanceMetadata(saved) {
    if (saved) metadataSaved++; else metadataSkipped++;
    metadataIndex++;
    while (metadataIndex < metadataQueue.length && !collection.some(entry => entry.id === metadataQueue[metadataIndex])) {
      metadataSkipped++; metadataIndex++;
    }
    if (metadataIndex === metadataQueue.length) {
      query("[data-library-status]").textContent = `Metadatenprüfung abgeschlossen · ${metadataSaved} übernommen · ${metadataSkipped} übersprungen.`;
      metadataDialog.close();
    } else {
      openMetadata(collection.find(entry => entry.id === metadataQueue[metadataIndex]),true);
    }
  }
  query("[data-metadata-next]").onclick = () => { if (!metadataBusy) advanceMetadata(false); };
  metadataSearch.onsubmit = event => {
    event.preventDefault();
    if (metadataBusy) return;
    metadataKey = "";
    metadataApply.hidden = true;
    query("[data-metadata-results]").replaceChildren();
    send("metadata-search",{id:metadataEntry.id,artist:metadataSearch.elements.artist.value.trim(),title:metadataSearch.elements.title.value.trim()});
  };
  metadataApply.onchange = updateMetadataSave;
  metadataApply.onsubmit = event => {
    event.preventDefault();
    if (metadataBusy || !metadataKey) return;
    const fields = [...metadataApply.querySelectorAll('input[type="checkbox"]:checked')].map(control => control.value);
    if (fields.length) send("metadata-apply",{id:metadataEntry.id,key:metadataKey,fields});
  };
  query("[data-metadata-source]").onclick = () => send("metadata-source",{id:metadataEntry.id,key:metadataKey});
  query("[data-metadata-genre-source]").onclick = () => send("metadata-source",{id:metadataEntry.id,key:metadataKey,field:"Genre"});
  function receiveMetadata(data) {
    if (!metadataDialog.open || data.id !== metadataEntry?.id) return;
    if (data.type === "metadata-status") {
      metadataBusy = !!data.busy;
      query("[data-metadata-status]").textContent = data.status || "";
      metadataSearch.querySelectorAll("input,button").forEach(control => control.disabled = metadataBusy);
      query("[data-metadata-results]").querySelectorAll("button").forEach(control => control.disabled = metadataBusy);
      query("[data-metadata-next]").disabled = metadataBusy;
      updateMetadataSave();
    } else if (data.type === "metadata-open") {
      if (metadataQueue.length && metadataSearch.elements.artist.value.trim() && metadataSearch.elements.title.value.trim()) metadataSearch.requestSubmit();
    } else if (data.type === "metadata-results") {
      const surface = query("[data-metadata-results]");
      surface.replaceChildren();
      for (const candidate of data.candidates) {
        const caption = [candidate.Artist,candidate.Title,candidate.Comment,candidate.Album,candidate.Date,candidate.Country,candidate.Format,candidate.Status].filter(Boolean).join(" · ");
        const control = button(caption,() => {
          metadataKey = "";
          metadataApply.hidden = true;
          surface.querySelectorAll("button").forEach(item => item.setAttribute("aria-pressed",String(item === control)));
          send("metadata-select",{id:metadataEntry.id,key:candidate.Key});
        });
        control.setAttribute("aria-pressed","false");
        surface.append(control);
      }
    } else if (data.type === "metadata-proposal") {
      metadataKey = data.key;
      query("[data-metadata-genre-source]").hidden = !data.values.Genre;
      const fields = query("[data-metadata-fields]");
      fields.replaceChildren();
      for (const [field,caption] of Object.entries(metadataLabels)) {
        const current = metadataEntry[field.toLowerCase()] || "";
        const proposal = data.values[field] || "";
        const row = element("tr");
        const cell = element("td");
        const label = element("label");
        const check = element("input");
        check.type = "checkbox";
        check.value = field;
        check.disabled = !proposal || current === proposal;
        check.checked = !!proposal && !current;
        label.append(check,document.createTextNode(caption));
        cell.append(label);
        row.append(cell,element("td",current || "—"),element("td",proposal || "Keine Angabe"));
        fields.append(row);
      }
      metadataApply.hidden = false;
      updateMetadataSave();
    } else if (data.type === "metadata-saved") {
      if (metadataQueue.length) advanceMetadata(true);
      else metadataDialog.close();
    }
  }
  function updateSelectionActions() {
    const entries = collection.filter(entry => checkedIds.has(entry.id));
    const tracks = entries.filter(entry => entry.kind === "Track");
    query("[data-selection-count]").textContent = `${entries.length} ausgewählt`;
    query("[data-clear-selection]").disabled = !entries.length;
    query("[data-bulk-delete]").disabled = !entries.length;
    query("[data-selection-playlist]").disabled = !entries.length;
    query("[data-bulk-metadata]").disabled = !tracks.length;
    query("[data-bulk-metadata]").textContent = tracks.length ? `Metadaten für ${tracks.length} Tracks prüfen` : "Metadaten prüfen";
  }
  function selectionCheck(entry) {
    const check = element("input");
    check.type = "checkbox";
    check.checked = checkedIds.has(entry.id);
    check.setAttribute("aria-label",entry.title + " auswählen");
    check.onchange = () => {
      lastTitleClick = {id:null,time:0};
      if (check.checked) checkedIds.add(entry.id); else checkedIds.delete(entry.id);
      updateSelectionActions();
    };
    return check;
  }
  query("[data-select-visible]").onclick = () => {
    for (const entry of visibleEntries) checkedIds.add(entry.id);
    render();
  };
  query("[data-clear-selection]").onclick = () => { checkedIds.clear(); render(); };
  query("[data-bulk-metadata]").onclick = () => {
    metadataQueue = collection.filter(entry => checkedIds.has(entry.id) && entry.kind === "Track").map(entry => entry.id);
    metadataIndex = metadataSaved = metadataSkipped = 0;
    if (metadataQueue.length) openMetadata(collection.find(entry => entry.id === metadataQueue[0]),true);
  };
  const deleteDialog = query("[data-delete-dialog]");
  const deleteForm = query("[data-delete-form]");
  let deleteToken = "";
  const requestDelete = ids => send("delete-preview",{ids});
  query("[data-bulk-delete]").onclick = () => requestDelete([...checkedIds]);
  for (const close of root.querySelectorAll("[data-close-delete]")) close.onclick = () => deleteDialog.close();
  deleteDialog.addEventListener("close",() => { send("delete-cancel"); deleteToken = ""; });
  deleteForm.onsubmit = event => {
    event.preventDefault();
    if (!deleteToken) return;
    deleteForm.querySelector('button[type="submit"]').disabled = true;
    send("delete-confirm",{token:deleteToken,originals:deleteForm.elements.originals.checked});
  };
  const downloadReview = query("[data-download-review-dialog]");
  const downloadReviewForm = query("[data-download-review-form]");
  let downloadReviewId = "";
  for (const close of root.querySelectorAll("[data-close-download-review]")) close.onclick = () => downloadReview.close();
  downloadReviewForm.onsubmit = event => {
    event.preventDefault();
    downloadReview.close();
    send("download-review-submit",{id:downloadReviewId,artist:downloadReviewForm.elements.artist.value.trim()});
  };
  query("[data-skip-download-review]").onclick = () => {
    downloadReview.close();
    send("download-review-submit",{id:downloadReviewId,skip:true});
  };
  function iconAction(icon, caption, invoke) {
    const control = button(icon, invoke);
    control.className = "detail-icon";
    control.title = caption;
    control.setAttribute("aria-label", caption);
    control.replaceChildren(drawIcon(icon),element("span",caption));
    return control;
  }
  function drawIcon(name) {
    const paths = {
      heart:'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z',
      trash:'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7',
      info:'M12 11v6m0-10v.1M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
      edit:'m15 4 5 5M4 20l5-1L21 7a2.1 2.1 0 0 0-5-5L4 14Z',
      export:'M12 16V2m-5 5 5-5 5 5M4 13v8h16v-8',
      folder:'M3 7V4h6l3 3h9v14H3Z',
      cover:'M3 3h18v18H3ZM3 17l6-6 4 4 3-3 5 5M8 7h.01',
      plus:'M12 3v18M3 12h18',
      playlist:'M3 5h15M3 10h15M3 15h8m5 3h6m-3-3v6',
      layers:'m12 2 10 6-10 6L2 8Zm-10 10 10 6 10-6M2 17l10 6 10-6',
      sets:'M7 3h14v14H7ZM3 7v14h14M11 7v6m4-6v6',
      music:'M9 18V5l12-3v13M9 9l12-3M9 18c0 4-7 4-7 0s7-4 7 0m12-3c0 4-7 4-7 0s7-4 7 0',
      download:'M12 2v14m-6-6 6 6 6-6M3 16v6h18v-6',
      convert:'M3 6h18m-4-4 4 4-4 4M21 18H3m4-4-4 4 4 4',
      settings:'M9 3h6l1 4 4 1v7l-4 1-1 5H9l-1-5-5-1V8l5-1ZM16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
      help:'M9 8a3 3 0 1 1 5 2c-2 1-2 2-2 3m0 4v.1M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
      filter:'M2 3h20l-8 9v9l-4-2v-7Z',
      grid:'M3 3h7v7H3Zm11 0h7v7h-7ZM3 14h7v7H3Zm11 0h7v7h-7Z',
      list:'M3 5h18M3 12h18M3 19h18',
      restart:'M3 10a9 9 0 1 1 0 6M3 3v7h7',
      previous:'M5 4v16M20 4 7 12l13 8Z',
      next:'M19 4v16M4 4l13 8-13 8Z',
      play:'m7 3 15 9-15 9Z',pause:'M8 4v16M16 4v16',
      stop:'M5 5h14v14H5Z',mini:'M2 3h20v18H2Zm9 10h8v5h-8Z',
      volume:'m11 3-6 5H2v8h3l6 5Zm4 4a7 7 0 0 1 0 10m3-14a12 12 0 0 1 0 18',
      record:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0M5 12a7 7 0 0 1 7-7m0 14a7 7 0 0 0 7-7'
    };
    const aliases={'♡':'heart','♥':'heart','🗑':'trash','ⓘ':'info','✎':'edit','⇥':'export','📁':'folder','▤':'folder','▧':'cover','＋':'playlist','↺':'restart'};
    const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
    svg.setAttribute('viewBox','0 0 24 24'); svg.setAttribute('aria-hidden','true');
    svg.setAttribute('fill','none'); svg.setAttribute('stroke','currentColor');
    svg.setAttribute('stroke-width','1.65'); svg.setAttribute('stroke-linecap','round'); svg.setAttribute('stroke-linejoin','round');
    const path=document.createElementNS(svg.namespaceURI,'path'); path.setAttribute('d',paths[aliases[name] || name] || paths.plus); svg.append(path);
    return svg;
  }
  for (const [selector,icon] of [['[data-kind=""]','layers'],['[data-kind="Set"]','sets'],['[data-kind="Track"]','music'],['[data-favorites]','heart'],['[data-open-playlists]','playlist'],['nav [data-command="downloads"]','download'],['nav [data-command="convert"]','convert'],['nav [data-command="settings"]','settings'],['[data-help]','help'],['[data-filter-toggle]','filter']]) {
    const control=query(selector); control.prepend(drawIcon(icon));
  }
  query('[data-favorites]').lastChild.textContent=' Favoriten';
  query('aside strong').prepend(drawIcon('record'));
  healthNav.prepend(drawIcon('help'));
  for(const [command,icon] of [['player-previous','previous'],['player-next','next'],['stop','stop'],['mini-player','mini']]) {
    query('footer [data-command="'+command+'"]').replaceChildren(drawIcon(icon));
  }
  query('footer .volume').prepend(drawIcon('volume'));
  for (const name of ['cover','list']) query('[data-view="'+name+'"]').replaceChildren(drawIcon(name==='cover'?'grid':'list'));
  query('[data-filter-toggle]').onclick=()=>{
    const panel=query('[data-filters]'); panel.hidden=!panel.hidden;
    query('[data-filter-toggle]').setAttribute('aria-expanded',String(!panel.hidden));
  };
  root.addEventListener('keydown',event=>{
    if(event.key==='Escape' && !query('[data-filters]').hidden){
      query('[data-filters]').hidden=true;query('[data-filter-toggle]').setAttribute('aria-expanded','false');query('[data-filter-toggle]').focus({preventScroll:true});
    }
  });
  query('[data-select-all-menu]').onclick=()=>query('[data-select-visible]').click();
  query('.toolbar').insertBefore(query('[data-count]'),query('.views'));
  function updateFilterChips() {
    const chips=query('[data-filter-chips]'); chips.replaceChildren();
    for(const {label,select} of filters) if(select.value){
      const chip=button(select.value+' ×',()=>{select.value='';render();});
      chip.title=label+' entfernen';chip.setAttribute('aria-label',label+' '+select.value+' entfernen');chips.append(chip);
    }
  }
  function updatePlayButton() {
    const canStart = root.dataset.mini !== "true" && visibleSelection && visibleSelection.id !== playback.id;
    const caption = canStart ? visibleSelection.title + " abspielen"
      : playback.playing ? "Pause" : playback.active ? "Wiedergabe fortsetzen"
      : visibleSelection ? visibleSelection.title + " abspielen" : "Abspielen";
    player.disabled = !visibleSelection && !playback.active;
    player.replaceChildren(drawIcon(!canStart && playback.playing ? 'pause' : 'play'));
    player.title = caption;
    player.setAttribute("aria-label",caption);
  }
  function updateNowPlaying() {
    const surface=query('[data-now]');
    surface.replaceChildren();
    const entry=collection.find(item=>item.id===playback.id);
    if(entry?.cover){const image=element('img');image.src=entry.cover;image.alt='';image.className='now-art';surface.append(image);}
    const copy=element('span');copy.className='now-copy';
    copy.append(element('strong',playback.title || 'Kein Titel ausgewählt'));
    if(entry?.artist) copy.append(element('small',entry.artist));
    surface.append(copy);
  }
  let filters = [];
  function createFilters() {
    const group = query("[data-filters]");
    group.replaceChildren();
    filters = Object.entries(schemas[kind]).filter(([key]) => key !== "date" && key !== "kind").map(([key, label]) => {
    const select = element("select");
    select.setAttribute("aria-label", label);
    group.append(select);
    select.addEventListener("change", render);
    return {key,label,select};
    });
    updateFilters();
  }
  const normalize = text => text.toLocaleLowerCase("de").normalize("NFD").replace(/\p{Diacritic}/gu, "");
  const values = (entry,key) => key === "artist"
    ? entry.artist.split(/\s+(?:&|b2b)\s+|,/i).map(name => name.trim())
    : key === "genre" ? (entry.genre || "").split(/[,;]/).map(name => name.trim()).filter(Boolean) : [entry[key]];
  function updateFilters() {
    for (const {key,label,select} of filters) {
      const previous = select.value;
      const options = [...new Set(collection.filter(entry => !kind || entry.kind === kind).flatMap(entry => values(entry,key)).filter(Boolean))]
        .sort((left,right) => left.localeCompare(right,"de"));
      select.replaceChildren(new Option(label + ": Alle",""), ...options.map(value => new Option(value)));
      select.value = options.includes(previous) ? previous : "";
    }
  }
  function picture(entry) {
    const frame = element("span");
    frame.className = "cover-art";
    frame.dataset.kind = entry.kind;
    const image = element("img");
    image.alt = "";
    image.className = "art";
    image.loading = "lazy";
    image.hidden = true;
    image.dataset.cover = entry.id;
    frame.append(image);
    if (!entry.hasCover) return frame;
    const observer = new IntersectionObserver(records => {
      if (!records.some(record => record.isIntersecting)) return;
      observer.disconnect();
      if (entry.cover) {
        image.src = entry.cover;
        image.hidden = false;
      } else {
        send("cover",{id:entry.id});
      }
    });
    observer.observe(frame);
    return frame;
  }
  function select(entry, event) {
    const now = performance.now();
    if (event?.detail > 0 && lastTitleClick.id === entry.id && now - lastTitleClick.time < 500) {
      lastTitleClick = {id:null,time:0};
      playEntry(entry);
      return;
    }
    lastTitleClick = event?.detail > 0 ? {id:entry.id,time:now} : {id:null,time:0};
    selected = entry.id;
    render();
    detail.querySelector("button")?.focus({preventScroll:true});
  }
  function render() {
    const main = query("[data-collection]");
    const scrollTop = main.scrollTop;
    const fields = schemas[kind];
    const playlist = playlists.find(list => list.id === activePlaylist);
    query("[data-active-playlist]").value = activePlaylist;
    query("[data-play-active-list]").disabled = !playlist || !playlist.items.some(item => !item.missing);
    query("[data-collection] h1").textContent = playlist?.name || (favoritesOnly ? "Favoriten" : kind === "Set" ? "Sets" : kind === "Track" ? "Tracks" : "Sammlung");
    const needle = normalize(search.value.trim());
    const matches = collection.filter(entry => (!kind || entry.kind === kind) && (!favoritesOnly || entry.favorite) &&
      (!playlist || playlist.items.some(item => item.id === entry.id)) &&
      normalize([entry.title,entry.originalTitle,...Object.keys(schemas[entry.kind] || fields).map(key => entry[key])].join(" ")).includes(needle) &&
      filters.every(({key,select}) => !select.value || values(entry,key).includes(select.value)));
    matches.sort((left,right) => {
      if (playlist) return playlist.items.findIndex(item => item.id === left.id) - playlist.items.findIndex(item => item.id === right.id);
      if (preferences.Sort === "year") return (Number(right.year) || 0) - (Number(left.year) || 0) || left.title.localeCompare(right.title,"de");
      const key = preferences.Sort === "title" ? "title" : "artist";
      return (left[key] || "").localeCompare(right[key] || "","de") || left.title.localeCompare(right.title,"de");
    });
    visibleEntries = matches;
    updateFilterChips();
    root.dataset.hasSelection=String(checkedIds.size>0);
    updateSelectionActions();
    query("[data-count]").textContent = matches.length === 1 ? "1 Eintrag" : matches.length + " Einträge";
    updateNavigation();
    root.querySelectorAll("[data-view]").forEach(control =>
      control.setAttribute("aria-pressed", String(control.dataset.view === view)));
    results.replaceChildren();
    results.className = view === "cover" ? "covers" : "";
    if (!matches.length) results.append(element("p", collection.length ? "Keine passenden Einträge." : "Füge Musik hinzu, um deine Sammlung zu starten."));
    if (view === "cover") {
      for (const entry of matches) {
        const card = button("", event => select(entry,event));
        const caption = element("span");
        card.className = "cover";
        card.setAttribute("aria-pressed", String(entry.id === selected));
        caption.append(element("strong",entry.title),element("br"),element("small",entry.artist || "DJ offen"));
        const line = entry.kind === "Track" ? [entry.year,entry.label || entry.album] : [entry.date || entry.year,entry.place];
        if (line.some(Boolean)) caption.append(element("br"),element("small",line.filter(Boolean).join(" · ")));
        const genre = element("small",entry.genre || "Genre offen");
        genre.className = "genre";
        caption.append(genre);
        card.append(picture(entry),caption);
        const wrapper = element("div");
        wrapper.className = "cover-card";
        wrapper.dataset.entryId = entry.id;
        const selection = element("label");
        selection.className = "cover-select";
        selection.append(selectionCheck(entry));
        const trash = iconAction("🗑",entry.title + " löschen",() => requestDelete([entry.id]));
        const tools = element("div");
        tools.className = "card-tools";
        tools.append(favoriteButton(entry));
        const operations = element("div");
        operations.className = "cover-operations";
        if (entry.kind === "Track") operations.append(iconAction("ⓘ","Metadaten ergänzen",() => openMetadata(entry)));
        tools.append(trash);
        wrapper.append(card,selection,tools,operations);
        results.append(wrapper);
      }
    } else if (matches.length) {
      const table = element("table");
      const headings = table.createTHead().insertRow();
      const rows = table.createTBody();
      const columns = Object.keys(fields).filter(key => kind !== "Set" || key !== "year");
      for (const caption of ["Auswahl","Titel",...columns.map(key => key === "date" ? "Datum / Jahr" : fields[key]),"Löschen"]) headings.append(element("th",caption));
      for (const entry of matches) {
        const row = rows.insertRow();
        row.dataset.entryId = entry.id;
        const selection = row.insertCell();
        selection.className = "selection-cell";
        selection.append(selectionCheck(entry));
        const open = button(entry.title,event => select(entry,event));
        open.setAttribute("aria-pressed",String(entry.id === selected));
        row.insertCell().append(open);
        for (const key of columns) row.insertCell().textContent = entry[key] || (key === "date" ? entry.year : "") || "–";
        row.insertCell().append(iconAction("🗑",entry.title + " löschen",() => requestDelete([entry.id])));
        row.onclick = event => { if (!event.target.closest("button,input,label")) select(entry,event); };
      }
      results.append(table);
    }
    const entry = matches.find(item => item.id === selected);
    visibleSelection = entry || null;
    updatePlayButton();
    detail.replaceChildren();
    detail.hidden = !entry;
    if (!entry) { main.scrollTop = scrollTop; return; }
    detail.append(picture(entry),element("h2",entry.title),element("p",entry.artist || "DJ offen"));
    const meta = element("dl");
    for (const [key,label] of Object.entries(schemas[entry.kind] || fields)) {
      if (key !== "artist" && (key !== "year" || !entry.date) && entry[key]) meta.append(element("dt",label),element("dd",entry[key]));
    }
    const controls = element("div");
    controls.className = "entry-actions";
    controls.append(iconAction("✎","Einordnung bearbeiten",() => send("edit",{id:entry.id})),
      iconAction("⇥","Exportieren",() => send("export",{id:entry.id})),
      iconAction("＋","Zur Playlist hinzufügen",() => openPlaylists([entry.id])),
      iconAction("📁","Ordner öffnen",() => send("folder",{id:entry.id})));
    if (!entry.external) controls.append(iconAction("▤","Ordner umbenennen",() => send("move",{id:entry.id})));
    controls.append(iconAction("▧","Cover ändern",() => openCoverEditor(entry)));
    controls.append(favoriteButton(entry));
    controls.append(iconAction("🗑","Track oder Set löschen",() => requestDelete([entry.id])));
    if (entry.kind === "Track") controls.append(iconAction("ⓘ","Metadaten ergänzen",() => openMetadata(entry)));
    if (entry.kind === "Set") controls.append(button("Trackliste",() => openTracklist(entry)),
      iconAction("↺","Set von Anfang an abspielen",() => playEntry(entry,true)));
    detail.append(meta,controls);
    const technical = element("p", audioInfo.get(entry.id) || "");
    technical.className = "muted";
    technical.dataset.audioInfo = "";
    detail.insertBefore(technical, controls);
    if (!audioInfo.has(entry.id)) {
      audioInfo.set(entry.id,"");
      send("audio-info",{id:entry.id});
    }
    main.scrollTop = scrollTop;
  }
  function renderDownloads(data) {
    query("[data-download-status]").textContent = data.status;
    const log = query("[data-download-log]");
    log.hidden = !data.log;
    log.querySelector("pre").textContent = data.log;
    query("[data-preview]").disabled = data.busy;
    const progress = query("[data-download-progress]");
    progress.hidden = !data.busy;
    if (data.percent === null) progress.removeAttribute("value");
    else progress.value = data.percent;
    for (const command of ["download","cancel-download","resume-queue","retry-queue"]) {
      query('[data-command="' + command + '"]').disabled = !data.actions[command];
    }
    const surface = query("[data-preview-rows]");
    if (surface.contains(document.activeElement) && data.rows.length && !data.busy) return;
    surface.replaceChildren();
    if (!data.rows.length) return;
    const table = element("table");
    const header = table.createTHead().insertRow();
    const body = table.createTBody();
    for (const caption of ["Laden","DJ","Titel","Typ","Status"]) header.append(element("th",caption));
    for (const item of data.rows) {
      const row = body.insertRow();
      for (const [field,caption] of [["selected","Zum Download auswählen"],["artist","DJ"],["title","Titel"],["kind","Typ"]]) {
        const control = element(field === "kind" ? "select" : "input");
        if (field === "selected") {
          control.type = "checkbox";
          control.checked = item.selected;
        } else if (field === "kind") {
          control.append(new Option("Set"),new Option("Track"));
          control.value = item.kind;
        } else {
          control.maxLength = 300;
          control.value = item[field];
        }
        control.setAttribute("aria-label",caption + " für " + item.title);
        control.disabled = data.busy || item.archived;
        control.onchange = () => send("edit-preview",{id:item.id,field,value:field === "selected" ? control.checked : control.value});
        row.insertCell().append(control);
      }
      row.insertCell().textContent = item.status;
    }
    surface.append(table);
  }
  function openEntryDialog(data) {
    entryAction = data.action;
    entryId = data.id;
    query("[data-entry-title]").textContent = data.title;
    query("[data-entry-submit]").textContent = data.submit;
    query("[data-entry-status]").textContent = "";
    namePreview.querySelector("output").textContent = "";
    const container = query("[data-entry-fields]");
    container.replaceChildren();
    for (const field of data.fields) {
      const label = element("label",field.label);
      if (field.only) label.dataset.only = field.only;
      if (field.name === "Artist") label.dataset.artistLabel = "";
      const input = element(field.options ? "select" : "input");
      if (field.name === "Genre") input.setAttribute("list","pk-genres");
      input.name = field.name;
      input.required = !!field.required;
      input.disabled = !!field.disabled;
      if (field.options) for (const option of field.options) input.append(new Option(option));
      input.value = field.value || "";
      if (field.name === "SetNameOverride") input.placeholder = "Leer lassen für automatischen Set-Namen";
      label.append(input);
      if (field.name === "destination") label.append(button("Durchsuchen …",() => send("export-browse")));
      container.append(label);
    }
    const type = entryForm.elements.namedItem("Type");
    if (type && entryAction === "edit") {
      const updateType = () => {
        for (const label of container.querySelectorAll("[data-only]")) {
          label.hidden = label.dataset.only !== type.value;
          label.querySelector("input,select").disabled = label.hidden;
        }
        container.querySelector("[data-artist-label]").firstChild.textContent = type.value === "Tracks" ? "Künstler" : "DJ";
        const date = entryForm.elements.namedItem("Date");
        const year = entryForm.elements.namedItem("Year");
        year.disabled = type.value === "Sets" && !!date.value.trim();
        year.parentElement.hidden = year.disabled;
      };
      type.onchange = updateType;
      entryForm.elements.namedItem("Date").oninput = updateType;
      updateType();
    }
    const format = entryForm.elements.namedItem("mode");
    if (format) {
      const bitrate = entryForm.elements.namedItem("bitrate");
      format.onchange = () => {bitrate.disabled = format.value === "Originalkopie";};
      format.onchange();
    }
    if (!entryDialog.open) entryDialog.showModal();
    refreshSetNamePreview();
  }
  entryForm.addEventListener("input", refreshSetNamePreview);
  entryForm.addEventListener("change", refreshSetNamePreview);
  query("[data-close-entry]").onclick = () => entryDialog.close();
  entryDialog.oncancel = event => { if (exporting) event.preventDefault(); };
  entryForm.onsubmit = event => {
    event.preventDefault();
    send(entryAction + "-submit",{id:entryId,values:Object.fromEntries(new FormData(entryForm))});
  };
  bridge.addEventListener("message", ({data}) => {
    if (data.type?.startsWith('health')) { window.dispatchEvent(new CustomEvent('pk-health',{detail:data}));return; }
    if (data.type.startsWith("metadata-")) { receiveMetadata(data); return; }
    if (data.type === "playlists") {
      playlists = data.lists;
      if (newPlaylistName) {
        const created = playlists.findLast(list => list.name === newPlaylistName);
        if (created) {
          playlistSelect.append(new Option(created.name,created.id));
          playlistSelect.value = created.id;
        }
        newPlaylistName = "";
      }
      renderPlaylists(); render();
      query("[data-playlist-status]").textContent = data.status || "";
    } else if (data.type === "playlist-status") {
      newPlaylistName = "";
      query("[data-playlist-status]").textContent = data.status;
      query("[data-library-status]").textContent = data.status;
    } else if (data.type === "library-status") {
      query("[data-library-status]").textContent = data.status;
    } else if (data.type === "mini") {
      root.dataset.mini = String(data.enabled);
      query("[data-mini-toggle]").title = data.enabled ? "Zur großen Ansicht" : "Mini-Player öffnen";
      query("[data-mini-toggle]").setAttribute("aria-label",query("[data-mini-toggle]").title);
      updatePlayButton();
    } else if (data.type === "download-review") {
      downloadReviewId = data.id;
      query("[data-download-review-title]").textContent = data.title;
      downloadReviewForm.elements.artist.value = data.artist || "";
      if (!downloadReview.open) downloadReview.showModal();
      downloadReviewForm.elements.artist.focus();
    } else if (data.type === "download-review-close") {
      downloadReview.close();
    } else if (data.type === "delete-preview") {
      deleteToken = data.token;
      query("[data-delete-items]").replaceChildren(...data.items.map(item => element("li",item.title)));
      const imported = data.items.some(item => item.external);
      query("[data-delete-originals]").hidden = !imported;
      query("[data-delete-imported]").hidden = !imported;
      query("[data-delete-managed]").hidden = data.items.every(item => item.external);
      deleteForm.elements.originals.checked = false;
      deleteForm.querySelector('button[type="submit"]').disabled = false;
      query("[data-delete-status]").textContent = "";
      if (!deleteDialog.open) deleteDialog.showModal();
    } else if (data.type === "delete-result") {
      for (const id of data.deleted) checkedIds.delete(id);
      query("[data-library-status]").textContent = data.status;
      deleteDialog.close();
      render();
    } else if (data.type === "delete-status") {
      query("[data-library-status]").textContent = data.status;
      query("[data-delete-status]").textContent = data.status;
      deleteForm.querySelector('button[type="submit"]').disabled = false;
    } else if (data.type === "collection") {
      const cached = new Map(collection.filter(entry => entry.cover).map(entry => [entry.id,entry.cover]));
      collection = data.entries.map(entry => ({...entry,cover:cached.get(entry.id)}));
      for (const id of checkedIds) if (!collection.some(entry => entry.id === id)) checkedIds.delete(id);
      if (!collection.some(entry => entry.id === selected)) selected = collection[0]?.id ?? null;
      updateFilters();
      render();
    } else if (data.type === "audio-info") {
      audioInfo.set(data.id,data.text);
      const technical = query("[data-audio-info]");
      if (data.id === selected && technical) technical.textContent = data.text;
    } else if (data.type === "cover-edit" && coverDialog.open && coverEntry?.id === data.id) {
      query("[data-cover-reset]").hidden = !data.custom;
    } else if (data.type === "cover-draft" && coverDialog.open && coverEntry?.id === data.id) {
      const preview = query("[data-cover-preview]");
      preview.src = data.image;
      preview.hidden = false;
      query("[data-cover-save]").disabled = false;
      query("[data-cover-status]").textContent = "Quadratischer Ausschnitt aus der Bildmitte.";
    } else if (data.type === "cover-edit-status" && coverDialog.open && coverEntry?.id === data.id) {
      query("[data-cover-status]").textContent = data.status || "";
      if (data.close) coverDialog.close();
    } else if (data.type === "cover") {
      const entry = collection.find(item => item.id === data.id);
      if (!entry) return;
      entry.cover = data.image;
      if (playback.id === entry.id) updateNowPlaying();
      for (const image of root.querySelectorAll("img[data-cover]")) {
        if (image.dataset.cover === entry.id) {
          if (entry.cover) image.src = entry.cover;
          else image.removeAttribute("src");
          image.hidden = !entry.cover;
        }
      }
    } else if (data.type === "player") {
      playback = data;
      updateTracklistPlayer();
      updateNowPlaying();
      query('[data-command="stop"]').disabled = !data.active;
      updatePlayButton();
      query('[data-command="player-next"]').disabled = !data.canNext;
      query('[data-command="player-previous"]').disabled = !data.canPrevious;
      seek.disabled = !data.duration;
      if (!seeking) {
        seek.max = data.duration || 1;
        seek.value = data.position || 0;
      }
      query("[data-time]").textContent = data.time;
    } else if (data.type === "tracklist-scan") {
      scans.set(data.id,data);
      if (tracklist.open && tracklistEntry?.id === data.id) showScan(data);
    } else if (data.type === "tracklist") {
      renderTracklist(data);
    } else if (data.type === "downloads") {
      renderDownloads(data);
    } else if (data.type === "settings") {
      if (data.folder !== undefined) settingsForm.elements.namedItem("folder").value = data.folder;
      if (data.theme !== undefined) {
        settingsForm.elements.namedItem("theme").value = data.theme;
        root.dataset.theme = data.theme === "System"
          ? (matchMedia("(prefers-color-scheme: light)").matches ? "Hell" : "Dunkel") : data.theme;
      }
      query("[data-settings-status]").textContent = data.status || "";
      if (data.preferences) applyPreferences(data.preferences);
    } else if (data.type === "diagnostics") {
      query("[data-diagnostic-report]").textContent = data.report;
      query("[data-diagnostic-status]").textContent = data.status;
      for (const command of ["diagnose-check","diagnose-yt","diagnose-ffmpeg","diagnose-deno"]) {
        query('[data-command="' + command + '"]').disabled = data.busy;
      }
    } else if (data.type === "page") {
      showPage(data.page);
    } else if (data.type === "convert") {
      if (data.files) query("[data-convert-files]").replaceChildren(...data.files.map(name => element("li",name)));
      if (data.destination !== undefined) convertForm.elements.namedItem("destination").value = data.destination;
      query("[data-convert-status]").textContent = data.status || "";
      query("[data-convert-report]").textContent = data.report || "";
      convertForm.querySelectorAll("input,select,button").forEach(control => control.disabled = !!data.busy);
      if (!data.busy) syncConvertFormat();
    } else if (data.type === "entry-dialog") {
      openEntryDialog(data);
    } else if (data.type === "set-name-preview") {
      if (entryDialog.open && !namePreview.hidden && data.id === entryId && data.revision === previewRevision) {
        namePreview.querySelector("output").textContent = data.title;
      }
    } else if (data.type === "entry-status") {
      exporting = !!data.busy;
      query("[data-entry-status]").textContent = data.status || "";
      query("[data-entry-submit]").disabled = exporting;
      query("[data-close-entry]").disabled = exporting;
      if (data.destination !== undefined) entryForm.elements.namedItem("destination").value = data.destination;
      if (data.close && entryDialog.open) entryDialog.close();
    } else if (data.type === "update") {
      query('[data-command="update"]').hidden = !data.available;
    }
  });
  search.addEventListener("input", render);
  for (const control of root.querySelectorAll("[data-kind]")) control.onclick = () => {
    favoritesOnly = false; activePlaylist = "";
    query("[data-active-playlist]").value = "";
    if (kind !== control.dataset.kind) {
      kind = control.dataset.kind;
      createFilters();
    }
    showCollection();
    render();
  };
  for (const control of root.querySelectorAll("[data-view]")) control.onclick = () => {
    view = control.dataset.view;
    try { localStorage.setItem("library-view",view); } catch {}
    render();
  };
  for (const control of root.querySelectorAll("[data-add]")) control.onclick = () => dialog.showModal();
  for (const control of root.querySelectorAll("[data-command]")) control.onclick = () => {
    if (dialog.open) dialog.close();
    if (help.open) help.close();
    if (restore.open) restore.close();
    const command = control.dataset.command;
    if (["downloads","youtube-search","youtube-link"].includes(command)) {
      showDownloads(command === "youtube-link" ? "links" : command === "youtube-search" ? "query" : null);
      send("downloads");
    } else if (["settings","diagnostics","convert","health"].includes(command)) {
      showPage(command);
      send(command);
    } else send(command);
  };
  settingsForm.onsubmit = event => {
    event.preventDefault();
    const values = {};
    for (const name of Object.keys(preferences)) {
      const control = settingsForm.elements.namedItem(name);
      values[name] = control.type === "checkbox" ? control.checked : control.type === "range" ? Number(control.value) : control.value;
    }
    send("settings-save",{folder:settingsForm.elements.namedItem("folder").value.trim(),
      theme:settingsForm.elements.namedItem("theme").value,preferences:values});
  };
  convertForm.onsubmit = event => {
    event.preventDefault();
    send("convert-start",{values:Object.fromEntries(new FormData(convertForm))});
  };
  query("[data-switch]").onclick = () => showDownloads(sourceMode === "query" ? "links" : "query");
  const playlistDialog = query("[data-playlist-dialog]");
  const playlistForm = query("[data-playlist-form]");
  let playlistLinks = "";
  query("[data-close-playlist]").onclick = () => playlistDialog.close();
  query("[data-cancel-playlist]").onclick = () => playlistDialog.close();
  playlistForm.onsubmit = event => {
    event.preventDefault();
    playlistDialog.close();
    send("preview-links",{value:playlistLinks,playlist:playlistForm.elements.whole.checked});
  };
  importForm.onsubmit = event => {
    event.preventDefault();
    const input = importForm.elements.namedItem(sourceMode);
    const value = input.value.trim();
    if (!value) { input.focus(); return; }
    if (sourceMode === "links" && value.split(/\s+/).some(link => {
      try { return new URL(link).searchParams.has("list"); } catch { return false; }
    })) {
      playlistLinks = value;
      playlistForm.elements.whole.checked = true;
      playlistDialog.showModal();
    } else {
      send(sourceMode === "query" ? "search-youtube" : "preview-links",{value});
    }
  };
  player.onclick = () => {
    if (root.dataset.mini === "true" && playback.active) {
      send("toggle");
    } else if (visibleSelection && (!playback.active || visibleSelection.id !== playback.id)) {
      playEntry(visibleSelection);
    } else if (playback.active) send("toggle");
  };
  seek.oninput = () => {seeking = true;};
  seek.onchange = () => {seeking = false; send("seek",{position:Number(seek.value)});};
  query("[data-volume]").onchange = event => send("volume",{value:Number(event.target.value)});
  createFilters();
  send("ready");
})();
