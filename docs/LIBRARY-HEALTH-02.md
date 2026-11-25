# Bibliothekspflege · Entwicklungsauftrag 02

Stand 24. November 2026. App-Version 0.5.1. Erweiterung des integrierten Moduls aus 0.5.0, kein neues Programm.

## Umsetzungsstand

Die ergänzte Bedienung mit einfacher und erweiterter Ansicht verwendet dieselben fachlichen Funktionen: [aktuelle Anleitung](BIBLIOTHEKSPFLEGE-BEDIENUNG.md), [nativer Prüfbericht vom 25. November 2026](BIBLIOTHEKSPFLEGE-PRUEFBERICHT-2026-11-25.md).

| Priorität | Umsetzung |
| --- | --- |
| P0 | Bestehende Scans/Transaktionen weiterverwendet. Strikte UTF-8-Prozessausgabe, NFC-Vergleich, semantische Metadatenstatus und separate Kennzeichnung eigener Dekodierungsfehler. Unter .NET mit ArgumentList werden Argumente einzeln übergeben; Windows PowerShell 5.1 verwendet die getestete native Windows-Quotierung ohne Shell. |
| P1 | Vorhandener Quelleneditor, Einzel-/Stapelplanung, Opus-/M4A-Reparatur, verifizierte Backups und Reporting erhalten. Mehrteilige Sets erhalten ein gemeinsames JSON mit getrennten Parts; alte Kategorieordner werden nicht ungeprüft umgeschrieben. |
| P2 | Datenbankkandidaten erkennen, selbst wählen, lesend mit aktuellen Audio-Tags vergleichen, Author/Title-Korrekturen planen, ausdrücklich freigeben und über XML-DOM ausführen. Unbekannte Versionen bleiben nur lesend. Rückgängig mit eigenem verifiziertem Vorschauschritt. |
| P3 | Vorhandene/eingebettete Cover und Original-Thumbnails vorbereiten, eigene Bilder und als KI-generiert gekennzeichnete Bilder importieren, gemeinsame Cover für ausgewählte Teile verwenden, JPEG in MP3 einbetten und identische Audioduplikate verifiziert archivieren/wiederherstellen. |
| P4 | Verbindlicher Abschlussvalidator aus 0.5.0 bleibt aktiv. JSON-/Audio-Titel werden semantisch verglichen. Keine erneute historische Massenreparatur. |
| P5 | Synthetische Audio-/XML-Tests, Fehler- und Rollbacktests, echte Hintergrund-Runspaces, UI-Prüfungen und Installer-Paketierung. Die Produktionsbibliothek und aktive VirtualDJ-Datenbank wurden hierfür nicht verändert. |

Die im Entwicklungsauftrag genannten 311 Dateien, 56 reparierten VirtualDJ-Einträge und neun semantischen Fälle sind bereitgestellte Praxisevidenz. Sie werden nicht als neue Scanergebnisse ausgegeben. Neustartpersistenz in VirtualDJ und vollständige Dekodierung der realen Sammlung bleiben separate praktische Prüfungen. Vorher-/Nachher-Screenshots sind im Auftrag beschrieben, diesem Textauftrag aber nicht als Bilddateien beigefügt.

## Technische Erweiterungen

- `DJ-Sets-HealthSemantic.ps1` normalisiert Vergleichswerte nach NFC/FormC, prüft Titel mit ausdrücklich vorhandenen Versions-, Genre- oder Labelzusätzen und unterscheidet EXACT_MATCH, SEMANTIC_MATCH, CONFLICT und REVIEW_REQUIRED. Es entfernt keine musikalischen Zusätze aus Dateien. Positive Statuscodes vermindern den Score nicht.
- `DJ-Sets-HealthVdj.ps1` liest XML ausschließlich mit nativem DOM, deaktivierter externer Auflösung und verbotenen DTDs. Es vergleicht die vom Parser dekodierten Pfade statt manuell maskierter XML-Zeichenketten. Die schreibende Freigabe gilt nur für die geprüfte Grundstruktur `VirtualDJ_Database Version="2026"`.
- `DJ-Sets-HealthCover.ps1` bereitet Cover vor und kapselt den separat getesteten MP3-Coverablauf. Vorhandene JPEGs werden ohne zusätzliche JPEG-Komprimierung übernommen. Andere Bilder können kontrolliert in JPEG umgesetzt werden. 1000 × 1000 ist die empfohlene Arbeitsgröße, keine erzwungene Neukodierung vorhandener Bilder.
- `DJ-Sets-HealthJson.ps1` rekonstruiert gemeinsame Setdaten mit `Parts[].FileName`, `Parts[].Tags` und separater Herkunft pro Teil. Bestehende unbekannte Felder bleiben erhalten. Mehrere nicht zugeordnete Tracks in einem Ordner benötigen weiterhin eine manuelle Strukturentscheidung.
- `DJ-Sets-HealthQuarantine.ps1` prüft identische Audiodaten, mindestens eine verbleibende Datei, PK-Verweise, Originalhashes und Archivkopien. Es gibt keine endgültige automatische Löschung.
- `DJ-Sets-HealthReports.ps1` sammelt Audio-, VirtualDJ- und Quarantänejournale für UTF-8-CSV und JSON. Alte eindeutig erkannte v1.3-CSV-Berichte sowie XML-Referenzsicherungen können lesend angezeigt werden. Ohne verifiziertes Zuordnungs-/Änderungsjournal wird eine alte XML-Datei nicht automatisch über die aktive Datenbank geschrieben.

Alle neuen Abläufe laufen über dieselbe WebView-Brücke und dieselben Hintergrundjobs. Bibliothek, Werkzeuge, Berichte, Backups, Quarantäne, Cover-Arbeitsordner und die ausgewählte Datenbank sind konfigurierbar. Die im Auftrag genannten D:-Pfade sind keine fest vorausgesetzten Programmkonstanten.

## Semantische und Unicode-Prüfung

Die neun bereitgestellten Varianten sind automatisierte Testfälle: Mahogany/Original Mix, Fathom/Dubstep, Basar/Sascha Braemer Edit, Fallen/Vex'd Remix, Marka/Exit Records, Closer/Original Mix, No Holds Barred/Excision Remix, She/Subfusc Remix und Howling/Âme Remix. Akzeptiert wird nur ein explizit passender Zusatz aus den zugehörigen Metadaten. Ein anderer Remix bleibt ein Konflikt.

Âme, Lumï, Sven Väth, Trentemøller, Björn Torwellen, Groß-Gerau, Täglich Brot und Nico's Deep Sea Edit werden zusätzlich durch echte native FFmpeg-/FFprobe-Aufrufe geprüft. Eine führende Â oder ein Umlaut allein gilt nicht als Fehler. Auffällige konkrete Mojibake-Muster und U+FFFD erzeugen einen Prüfhinweis, keine automatische Zeichenersetzung. Ungültige UTF-8-Werkzeugausgabe erhält `TOOL_ENCODING_ERROR` statt die Audiodatei als defekt zu klassifizieren.

Die lokalen Korrekturentscheidungen zu Dadub, Data, DOM, Didjelirium und der RPR-1-Maximal-Tributesendung sind Referenzfälle für manuelle Quellenentscheidungen. Sie sind keine globalen Künstler-/Titelregeln und wurden nicht als automatische Umbenennungsmuster implementiert.

## VirtualDJ benutzen

1. Zuerst die gewünschte Bibliothek scannen. Im Bereich **VirtualDJ / Poweramp** auf **Datenbanken erkennen** klicken oder den Pfad manuell in den Pflege-Einstellungen angeben.
2. Kandidaten nach Version, Eintragszahl und Bibliothekstreffern beurteilen. Es erfolgt keine automatische Wahl anhand des Datums. Die gewünschte Datenbank ausdrücklich übernehmen und speichern.
3. **Gewählte Datenbank lesend analysieren**. Die Tabelle trennt fehlende/ungültige Datenbank-Tags, echte vorhandene Konflikte, fehlende Einträge und verwaiste Verknüpfungen. Korrekte Audio-Tags bleiben unangetastet. Fehlende/verwaiste Einträge werden nicht automatisch angelegt oder gelöscht.
4. Reparierbare Einträge auswählen und eine Vorschau erstellen. Vor der Freigabe VirtualDJ vollständig schließen. Der Prozessstatus wird vor Beginn und erneut vor dem Austausch kontrolliert. Eine laufende VirtualDJ-Instanz blockiert die Änderung.
5. Freigegeben werden ausschließlich die angezeigten `Tags.Author`- und `Tags.Title`-Werte aus aktuellen Audio-Tags. Bereits vorhandene, nicht generische abweichende Werte erfordern manuelle Klärung.

Der Ablauf erstellt ein SHA-256-verifiziertes vollständiges Backup, klont das DOM und erzeugt eine temporäre XML-Datei. Der Writer verwendet `NewLineHandling.None`; der ursprüngliche UTF-8-BOM-Zustand wird aus den tatsächlichen Bytes EF BB BF erkannt und erhalten. Die Datei wird erneut geparst. Nach Prüfung von Anzahl/Reihenfolge und Zielattributen werden die erlaubten Änderungen in einer Vergleichskopie zurückgenommen. Deren gesamtes DOM muss dem Original entsprechen. Damit werden unter anderem Flag, Infos, Scan, Poi, BPM, Beatgrids, Cues, Gain, AudioSig und unbekannte Inhalte geschützt.

Datei- und Audioquellen werden vor dem Austausch erneut auf Änderungen geprüft. `File.Replace` erstellt eine zusätzliche Austausch-Sicherung. Nach dem Austausch folgen Hash- und XML-Prüfung; Fehler lösen Rollback aus. Eine späte fremde Änderung im Austausch-Backup wird beim Rücksetzen nicht durch einen älteren Stand ersetzt.

Dies ist ein versionsabhängiger Kompatibilitäts-Workaround, keine zugesicherte offizielle VirtualDJ-API. Der genaue Grund des beschriebenen M4A-Einleseproblems bleibt ungeklärt. Eine Anzeige-/Wiedergabeprüfung nach anschließendem VirtualDJ-Neustart muss auf dem betreffenden Gerät erfolgen. Die Anwendung behauptet diesen Test nicht als abgeschlossen.

## Cover und mehrteilige Sets

Im Quelleneditor **Cover aus vorhandener Quelle / Original-Thumbnail vorbereiten** wählen. Vorrang haben eingebettetes Cover und lesbares externes Cover. Erst danach wird eine vorhandene YouTube-Video-ID aus info.json für einen kontrollierten Abruf bei `i.ytimg.com` verwendet. Fehlende/ungültige Maxres-Bilder erhalten einen HQ-Fallback. Andere Downloadhosts und ungeprüfte Thumbnail-URLs werden nicht beliebig aufgerufen. Vorbereitung verändert nur den konfigurierten Arbeitsordner. Quelle und Bildvorschau werden vor der Freigabe gezeigt.

Eigene Bilder lassen sich importieren und bei Bedarf ausdrücklich als KI-generiert kennzeichnen. Die Kennzeichnung wird in MetadataSources gespeichert; ein alternatives Bild wird nicht als offizielles Veranstaltungsfoto ausgegeben. Ein kostenpflichtiger KI-Bilderdienst ist nicht angebunden. Die optionale eigene Bilderzeugung bleibt extern; PK kann deren Ergebnisse verwalten.

Für mehrere Teile in der Scanansicht die Dateien auswählen und **Gemeinsames Cover für Auswahl** öffnen. Bei einer reinen MP3-Auswahl kann zusätzlich **in MP3 einbetten** aktiviert werden. Einzelne Audio-Tags bleiben in diesem Cover-Stapelmodus unverändert. Externe Cover werden gemeinsam im Setordner gespeichert; eingebettete Bilder gehören zur jeweiligen MP3.

Die Einbettung kopiert die kodierten Audiospuren und das JPEG, setzt ID3v2.3/attached_pic und prüft anschließend Audiohashes, Codec-/Konfigurations-/Zeitparameter, vorhandene Musik-Tags und das tatsächlich eingebettete JPEG. Andere Audioformate sind nicht für diese neue Einbettungsmethode freigegeben. Opus/M4A-Tagreparaturen und die Erhaltung bestehender zusätzlicher Streams funktionieren weiterhin getrennt.

## Quarantäne und Wiederherstellung

Identische Audioduplikate in der Scanansicht auswählen. Der Plan nennt die zu archivierende Datei, vollständigen Dateihash, eine verifizierte Behaltensdatei sowie bekannte externe VirtualDJ-Verweise. Mindestens eine identische Datei bleibt erhalten. Von PK-Playlisten oder Favoriten referenzierte Dateien sind gesperrt, bis diese Verweise in PK geändert wurden. Weitere externe Verweise müssen ausdrücklich als geprüft bestätigt werden.

Nach Freigabe entstehen vollständige verifizierte Originalkopien im Backup- und Quarantäneordner. Erst danach wird die ausgewählte Quelldatei aus dem normalen Bibliothekspfad entfernt. Begleitdateien werden nicht pauschal mitgelöscht. Ein Journaleintrag dokumentiert Originalpfad, Hash, Behaltensdatei, Referenzen und Zustand. Keine Sicherung wird automatisch endgültig gelöscht.

Unter **Quarantäne** die Wiederherstellung prüfen und getrennt freigeben. Am Originalpfad vorhandene fremde Dateien werden nicht überschrieben. Das wiederhergestellte Audio muss den ursprünglichen vollständigen Dateihash besitzen. Unter **Backup & Restore** lassen sich VirtualDJ-Backups getrennt von Audio-Reparaturbackups wiederherstellen. Ein fremd veränderter Datenbankstand sperrt das automatische Zurücksetzen.

Mehrere Audio-Reparaturen mit gemeinsamem Set-JSON/Cover werden innerhalb eines Auftrags anhand verifizierter eigener Änderungen fortgeführt. Fremde Änderungen bleiben gesperrt. Das Rückgängigmachen einer zusammengehörigen Auswahl wird vorab als rückwärts geordnete Hashkette simuliert und dann in umgekehrter Reihenfolge ausgeführt. Dadurch bleiben ursprüngliche JSON-/Coverzustände nachvollziehbar.

## Tests und Releasegrenzen

`build/Test-Health.ps1` führt die bisherigen Tests und die Erweiterungen aus. Für Auftrag 02 kommen `Health02.Tests.ps1` und `Health02.UI.cjs` hinzu. Enthalten sind BOM an/aus, CRLF, Entities, Apostrophe/Ampersands/Unicode in Pfaden, unbekannte XML-Felder, Cue-/BPM-Erhalt, fremde Änderungen, Dateisperren, laufendes VirtualDJ, ungültiges temporäres XML, Fehler nach dem Austausch und bytegenaue Wiederherstellung. MP3-Cover, mehrteilige Set-Aufträge, Quarantäne und native UTF-8-Kommunikation werden mit synthetischen Dateien geprüft.

Auf produktive Musik- und Datenbankdateien wurde kein Test-Reparaturauftrag angewendet. Neue kostenpflichtige Dienste wurden nicht gebucht. Weitere Datenbankversionen, akustisches Fingerprinting, echte KI-Bildgenerierung und automatische Pflege fremder Playlisten bleiben ausdrücklich außerhalb dieser Freigabe. Eine unbekannte Version wird niemals allein wegen ähnlicher XML-Form schreibend freigegeben.

Referenzen: [VirtualDJ-Handbuch](https://virtualdj.com/manuals/virtualdj.html), [FFmpeg: Mapping, Stream Copy und Metadaten](https://ffmpeg.org/ffmpeg.html), [FFprobe](https://ffmpeg.org/ffprobe.html), [FFmpeg: Container und Hash-Muxer](https://ffmpeg.org/ffmpeg-formats.html). Die dokumentierte manuelle Tag-Neueinlesung bleibt eine Alternative zur direkten versionsgebundenen XML-Pflege.
