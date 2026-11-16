(() => {
  const bridge = window.chrome.webview;
  const root = document.getElementById("pk-concept");
  const query = selector => root.querySelector(selector);
  const schemas = {
    "": {artist:"Künstler / DJ",year:"Jahr",kind:"Typ"},
    Track: {artist:"Künstler",album:"Album",year:"Jahr"},
    Set: {artist:"DJ",date:"Aufnahmedatum",year:"Jahr",series:"Set-Reihe",event:"Veranstaltung",place:"Location"}
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
  const audioInfo = new Map();
  try { if (localStorage.getItem("library-view") === "list") view = "list"; } catch {}
  let seeking = false, page = "collection", sourceMode = "query";
  let playback = { id:null, active:false, playing:false }, visibleSelection = null;
  const importForm = query("[data-youtube]");
  query("[data-help]").onclick = () => help.showModal();
  query("[data-restore]").onclick = () => restore.showModal();
  function showPage(next) {
    if (page === "downloads" && next !== page) send("refresh");
    page = next;
    for (const name of ["collection","downloads","settings","diagnostics","convert"]) {
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
      control.setAttribute("aria-pressed", String(page === "collection" && control.dataset.kind === kind));
    }
    for (const name of ["downloads","settings","convert"]) {
      query('nav [data-command="' + name + '"]').setAttribute("aria-pressed", String(page === name));
    }
    query("[data-help]").setAttribute("aria-pressed", String(page === "diagnostics"));
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
  function iconAction(icon, caption, invoke) {
    const control = button(icon, invoke);
    control.className = "detail-icon";
    control.title = caption;
    control.setAttribute("aria-label", caption);
    return control;
  }
  function updatePlayButton() {
    const canStart = visibleSelection && visibleSelection.id !== playback.id;
    const caption = canStart ? visibleSelection.title + " abspielen"
      : playback.playing ? "Pause" : playback.active ? "Wiedergabe fortsetzen"
      : visibleSelection ? visibleSelection.title + " abspielen" : "Abspielen";
    player.disabled = !visibleSelection && !playback.active;
    player.textContent = !canStart && playback.playing ? "Ⅱ" : "▶";
    player.title = caption;
    player.setAttribute("aria-label",caption);
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
    ? entry.artist.split(/\s+(?:&|b2b)\s+|,/i).map(name => name.trim()) : [entry[key]];
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
    const image = element("img");
    image.alt = "";
    image.className = "art";
    image.loading = "lazy";
    image.hidden = true;
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
        image.dataset.cover = entry.id;
      }
    });
    observer.observe(frame);
    return frame;
  }
  function select(entry) {
    selected = entry.id;
    render();
    detail.querySelector("button")?.focus();
  }
  function render() {
    const fields = schemas[kind];
    query("[data-collection] h1").textContent = kind === "Set" ? "Sets" : kind === "Track" ? "Tracks" : "Sammlung";
    const needle = normalize(search.value.trim());
    const matches = collection.filter(entry => (!kind || entry.kind === kind) &&
      normalize([entry.title,entry.originalTitle,...Object.keys(schemas[entry.kind] || fields).map(key => entry[key])].join(" ")).includes(needle) &&
      filters.every(({key,select}) => !select.value || values(entry,key).includes(select.value)));
    query("[data-count]").textContent = matches.length === 1 ? "1 Eintrag" : matches.length + " Einträge";
    updateNavigation();
    root.querySelectorAll("[data-view]").forEach(control =>
      control.setAttribute("aria-pressed", String(control.dataset.view === view)));
    results.replaceChildren();
    results.className = view === "cover" ? "covers" : "";
    if (!matches.length) results.append(element("p", collection.length ? "Keine passenden Einträge." : "Füge Musik hinzu, um deine Sammlung zu starten."));
    if (view === "cover") {
      for (const entry of matches) {
        const card = button("", () => select(entry));
        const caption = element("span");
        card.className = "cover";
        card.setAttribute("aria-pressed", String(entry.id === selected));
        caption.append(element("strong",entry.title),element("br"),element("small",entry.artist || "DJ offen"));
        const line = entry.kind === "Track" ? [entry.album,entry.year] : [entry.date || entry.year,entry.place];
        if (line.some(Boolean)) caption.append(element("br"),element("small",line.filter(Boolean).join(" · ")));
        card.append(picture(entry),caption);
        results.append(card);
      }
    } else if (matches.length) {
      const table = element("table");
      const headings = table.createTHead().insertRow();
      const rows = table.createTBody();
      const columns = Object.keys(fields).filter(key => kind !== "Set" || key !== "year");
      for (const caption of ["Titel",...columns.map(key => key === "date" ? "Datum / Jahr" : fields[key])]) headings.append(element("th",caption));
      for (const entry of matches) {
        const row = rows.insertRow();
        const open = button(entry.title,() => select(entry));
        open.setAttribute("aria-pressed",String(entry.id === selected));
        row.insertCell().append(open);
        for (const key of columns) row.insertCell().textContent = entry[key] || (key === "date" ? entry.year : "") || "–";
      }
      results.append(table);
    }
    const entry = matches.find(item => item.id === selected);
    visibleSelection = entry || null;
    updatePlayButton();
    detail.replaceChildren();
    detail.hidden = !entry;
    if (!entry) return;
    detail.append(picture(entry),element("h2",entry.title),element("p",entry.artist || "DJ offen"));
    const meta = element("dl");
    for (const [key,label] of Object.entries(schemas[entry.kind] || fields)) {
      if (key !== "artist" && (key !== "year" || !entry.date) && entry[key]) meta.append(element("dt",label),element("dd",entry[key]));
    }
    const controls = element("div");
    controls.className = "entry-actions";
    controls.append(iconAction("✎","Einordnung bearbeiten",() => send("edit",{id:entry.id})),
      iconAction("⇥","Exportieren",() => send("export",{id:entry.id})),
      iconAction("📁","Ordner öffnen",() => send("folder",{id:entry.id})));
    if (!entry.external) controls.append(iconAction("▤","Ordner umbenennen",() => send("move",{id:entry.id})));
    detail.append(meta,controls);
    const technical = element("p", audioInfo.get(entry.id) || "");
    technical.className = "muted";
    technical.dataset.audioInfo = "";
    detail.insertBefore(technical, controls);
    if (!audioInfo.has(entry.id)) {
      audioInfo.set(entry.id,"");
      send("audio-info",{id:entry.id});
    }
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
    if (data.type === "collection") {
      const cached = new Map(collection.filter(entry => entry.cover).map(entry => [entry.id,entry.cover]));
      collection = data.entries.map(entry => ({...entry,cover:cached.get(entry.id)}));
      if (!collection.some(entry => entry.id === selected)) selected = collection[0]?.id ?? null;
      updateFilters();
      render();
    } else if (data.type === "audio-info") {
      audioInfo.set(data.id,data.text);
      const technical = query("[data-audio-info]");
      if (data.id === selected && technical) technical.textContent = data.text;
    } else if (data.type === "cover") {
      const entry = collection.find(item => item.id === data.id);
      if (!entry || !data.image) return;
      entry.cover = data.image;
      for (const image of root.querySelectorAll("img[data-cover]")) {
        if (image.dataset.cover === entry.id) {
          image.src = entry.cover;
          image.hidden = false;
        }
      }
    } else if (data.type === "player") {
      playback = data;
      query("[data-now]").textContent = data.title;
      query('[data-command="stop"]').disabled = !data.active;
      updatePlayButton();
      seek.disabled = !data.duration;
      if (!seeking) {
        seek.max = data.duration || 1;
        seek.value = data.position || 0;
      }
      query("[data-time]").textContent = data.time;
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
    } else if (["settings","diagnostics","convert"].includes(command)) {
      showPage(command);
      send(command);
    } else send(command);
  };
  settingsForm.onsubmit = event => {
    event.preventDefault();
    send("settings-save",{folder:settingsForm.elements.namedItem("folder").value.trim(),
      theme:settingsForm.elements.namedItem("theme").value});
  };
  convertForm.onsubmit = event => {
    event.preventDefault();
    send("convert-start",{values:Object.fromEntries(new FormData(convertForm))});
  };
  query("[data-switch]").onclick = () => showDownloads(sourceMode === "query" ? "links" : "query");
  importForm.onsubmit = event => {
    event.preventDefault();
    const input = importForm.elements.namedItem(sourceMode);
    if (input.value.trim()) send(sourceMode === "query" ? "search-youtube" : "preview-links",{value:input.value.trim()});
    else input.focus();
  };
  player.onclick = () => {
    if (visibleSelection && (!playback.active || visibleSelection.id !== playback.id)) {
      send("play",{id:visibleSelection.id});
    } else if (playback.active) send("toggle");
  };
  seek.oninput = () => {seeking = true;};
  seek.onchange = () => {seeking = false; send("seek",{position:Number(seek.value)});};
  query("[data-volume]").onchange = event => send("volume",{value:Number(event.target.value)});
  createFilters();
  send("ready");
})();
