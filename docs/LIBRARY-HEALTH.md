# Bibliothekspflege · Library Health & Repair Center

Stand 24. November 2026. Erste integrierte Version des Moduls, App-Entwicklungsstand 0.5.0.

## Bestandsaufnahme und Architekturentscheidung

Plattenkoffer ist eine Windows-Anwendung mit einer PowerShell-5.1-kompatiblen WinForms-Hülle, WebView2 und lokalem HTML/JavaScript. Die neuen Funktionen verwenden dieselbe Oberfläche, Nachrichtenbrücke, Tools und PowerShell-Runspaces. Ein zusätzliches Framework, eine Datenbank, ein Server oder ein kostenpflichtiger Dienst ist nicht erforderlich.

Vor Beginn lag der lokale Stand 0.4.9 mit uncommitteten Änderungen aus den bisherigen Aufgaben vor. Die Entwicklung erfolgt auf `codex/library-health-center`. Bestehende Sammlung, Downloads, Metadatenprüfung, Playlisten, Favoriten, Player und Konfigurationssicherung bleiben erhalten. Die vorhandenen Pflegeprotokolle vom 23. November sind keine aktuellen Scanergebnisse und lösen keine automatischen Änderungen aus.

Die Bestandsaufnahme bestätigte folgende Datenorte und Abläufe:

- Verwaltete Einträge liegen gewöhnlich unter `Interpret/Tracks/Titel` oder `DJ/Sets/Setname`. Im Musikordner liegen aber auch abweichende Strukturen. Der neue Scanner findet Audiodateien rekursiv und kennzeichnet solche Abweichungen.
- `plattenkoffer.json` enthält überwiegend Zeichenketten wie Artist, Title, Album, Year, Label, Version, Genre, Date, Series, Event, Location und SetNameOverride sowie das Objekt MetadataSources. Bestehende unbekannte Felder bleiben bei Änderungen erhalten.
- `info.json` enthält die ursprünglichen Quelleninformationen und wird nicht verändert.
- Bei extern verknüpften Dateien liegen Sammlungsangaben teilweise in `dj-set-local-library.json`, eigene Cover und Tracklisten im Konfigurationsordner. Der neue Scanner ist an den ausdrücklich gewählten Scanordner gebunden und verfolgt keine Verknüpfungen zu anderen Datenträgern.
- Die bisherige Download-Pipeline übernahm die Audiospur verlustfrei und kopierte Cover und info.json. Sie schrieb dabei nicht verbindlich bestätigte Artist-/Title-Tags und kein konsistentes PK-JSON. Das ist im aktuellen Code nachvollziehbar. Die Entstehungsgeschichte jeder älteren Datei ist damit nicht bewiesen.

## Komponenten

| Datei | Verantwortung |
| --- | --- |
| `setup/DJ-Sets-Health.ps1` | Lokaler Prozessaufruf, Pfadprüfung, FFprobe, Tags, Quellenauflösung, Coverdiagnose, Scan, Checkpoints, Duplikate und Dashboardwerte |
| `setup/DJ-Sets-HealthRepair.ps1` | Dry Run, Backup-Prüfung, Stream Copy, Freigabe, Validierung, Austausch, Rollback und Wiederherstellung |
| `setup/DJ-Sets-HealthWeb.ps1` | Bestehende WebView-Brücke, Hintergrundjobs, Fortschritt, Optionen, Protokolle und native Dateiauswahl |
| `setup/ui/health.js` | Dashboard, Tabelle, Filter, Quelleneditor, Reparaturvorschau, Freigaben und Backupauswahl |
| `setup/DJ-Sets-DownloadValidation.ps1` | Tags, Cover-/JSON-Prüfung, Audiohash und Dekodierung vor der Veröffentlichung eines neuen Downloads |

Die Werkzeuge laufen mit absoluten, konfigurierbaren Pfaden, ohne Shell und mit Windows-Argumentquotierung. FFmpeg und FFprobe dürfen in diesem Modul ausschließlich lokale Datei-/Pipe-Protokolle öffnen. Native Prozesse haben ein Zeitlimit und können während eines Abbruchs beendet werden. Es läuft nur ein Pflegejob gleichzeitig. Schreibende Pflegejobs sperren konkurrierende Wiedergabe, Downloads, Änderungen und Updates.

## Bedienung

1. **Bibliothekspflege** öffnen. Unter **Ordner, Werkzeuge und Scanoptionen** Scanordner, FFprobe, FFmpeg, Backupordner und Speicherlimit kontrollieren. Standard ist die aktuelle Musikbibliothek; Backups liegen separat unter den eigenen Dokumenten. Das Speicherlimit beträgt zunächst 20 GB. 0 bedeutet unbegrenzt. Backups werden nie automatisch gelöscht.
2. **Vollständig scannen** führt eine neue Untersuchung durch. **Inkrementell / fortsetzen** verwendet unveränderte Dateiergebnisse erneut. Ein angekreuzter Tiefenscan erzwingt die vollständige Audiodekodierung für noch nicht entsprechend geprüfte Dateien. Für einen vollständig neuen Tiefenscan die vollständige Scan-Schaltfläche verwenden.
3. Ergebnisse nach fehlenden Tags, JSON, Konflikten, Covern, Duplikaten, Audiofehlern, Struktur oder Typ filtern. Die Tabelle lässt sich horizontal scrollen und zeigt jeweils bis zu 100 Dateien. Kennzahlen verwenden tatsächliche Ergebnisse und zählen betroffene Dateien statt Fehlercodes.
4. **Prüfen / bearbeiten** zeigt Audio-Tags, PK-Daten, Ordner- und Quellenhinweise. Nur angekreuzte Felder werden geändert. Eine Quelle lässt sich gezielt übernehmen. Optional vorhandene Tags zur JSON-Rekonstruktion auswählen oder ein eigenes Cover vorsehen.
5. **Reparaturvorschau erstellen** verändert keine Musikdateien. Die Vorschau nennt alte/neue Werte, Quellen, Konflikte, betroffene Pfade und mindestens benötigten Backupplatz. Erst das ausdrückliche Ankreuzen der Freigabe ermöglicht die Ausführung.
6. Für eine Stapelvorschau gefilterte oder einzelne Dateien auswählen. Die automatische Vorauswahl ergänzt nur fehlenden Interpret/Titel ohne erkannten Quellenkonflikt. Bereits korrekte Tags werden dabei nicht neu geschrieben.
7. Nach einer Änderung erneut scannen. Unter **Reparaturen** sind Ergebnisse und eine neue Vorschau für noch nicht erfolgreich bearbeitete Dateien erreichbar. Jede erneute Vorschau verlangt eine neue Freigabe und einen aktuellen Scanstand.

Der Score verwendet ausschließlich vollständig dekodierte Dateien. Eine bestandene FFprobe-/Paketprüfung allein gilt nicht als vollständiger Integritätsnachweis. Hinweise auf generische Namen oder ein fehlendes eingebettetes Cover machen eine Datei nicht automatisch defekt. Ein veränderter oder nicht mehr erreichbarer Eintrag wird am Scanende als veraltet markiert und muss erneut geprüft werden.

## Metadaten und Quellen

Felder werden einzeln aufgelöst. Als bestätigt dokumentierte PK-Felder kommen zuerst, danach gültige Audio-Tags, weitere PK-Angaben, die erkennbare Ordnerstruktur, strukturierte info.json-Felder und zuletzt der Videotitel. Widersprüche bleiben sichtbar und verhindern automatische fehlende-Tag-Vorschläge für das jeweilige Feld. Ein Uploader-/Kanalname wird nicht zum Interpreten erklärt. Sets erhalten keine automatische Interpret-/Titeltrennung aus dem Videotitel.

Die konfigurierbare Bereinigung entfernt bekannte Videozusätze in abschließenden Klammern. Musikalische Versionen wie Extended Mix, Remix, Radio Edit oder Live Version bleiben stehen. Herkunft, frühere und bestätigte Werte, Bestätigungszeit, manuelle Übernahme und die Kategorien VERIFIED, HIGH_CONFIDENCE, MEDIUM_CONFIDENCE, LOW_CONFIDENCE werden nachvollziehbar gespeichert. Es werden keine Prozentwahrscheinlichkeiten erfunden.

Beim Schreiben werden vorhandene PK-Objekte gelesen und gezielt ergänzt. `HealthSchemaVersion: 1` versioniert die Erweiterung, ohne alte Dateien pauschal umzuschreiben. Unbekannte Health-Schemaversionen und beschädigte JSON-Dateien sperren schreibende Reparaturen.

## Sicherheitsablauf und unterstützte Formate

Schreibend freigegeben sind zunächst **Opus im Ogg-Container mit der Endung .opus** und **AAC in .m4a**, jeweils mit einer Audiospur. MP3, FLAC, Ogg/Vorbis, WAV, WebM, AIFF und andere erkannte Formate sind zunächst nur lesend freigegeben. Vorhandene zusätzliche Streams und eingebettete Cover müssen beim Tag-Schreiben erhalten bleiben. Ihre Streamparameter und bei zusätzlichen Streams auch ihre Prüfsummen werden verglichen.

Vor jeder produktiven Reparatur werden Existenz, vollständiger Audio-Dateihash und Begleitdateistand erneut geprüft. Die Originale einschließlich vorhandener PK-/Quell-JSONs und Cover werden vollständig kopiert und per SHA-256 verifiziert. Speicherplatz und konfiguriertes Backup-Limit werden vorab geprüft. Ein bestehendes Reparaturverzeichnis wird nicht überschrieben.

Eine neue Datei entsteht im selben Ordner unter einem ausgeschlossenen temporären Namen. FFmpeg verwendet ausschließlich Stream Copy. Die SHA-256-Prüfsummen jeder kodierten Audiospur müssen übereinstimmen. Streamanzahl, Codec, Profil, Abtastrate, Kanäle, Kanalbelegung, Dauer und relevante Bildparameter werden verglichen. Pflicht- und nicht ausgewählte bekannte Metadaten werden erneut gelesen und geprüft. Vor der Reparatur wird das Original vollständig dekodiert. Erst dann erfolgt der kontrollierte Dateiaustausch am ursprünglichen Pfad mit anschließender erneuter Prüfung. Bei einem Fehler werden bereits geänderte Dateien zurückgesetzt.

Es gibt keine automatische Umbenennung, Duplikatlöschung, Hochkonvertierung oder Neukodierung. Datei- und Audioprüfsummen werden getrennt verwendet. Duplikate werden anhand der gesamten Datei, identischer kodierter Audiospuren und konservativer Metadaten-/Dauerähnlichkeit vorgeschlagen; unterschiedliche Versionen bleiben getrennt.

## Backup, Wiederanlauf und Protokolle

Die normale Konfigurations-ZIP sichert zusätzlich `health-options.json`, ersetzt aber kein Audio-Reparaturbackup. Reparaturbackups sind nach Auftrag und Datei-ID gegliedert. Die Originale heißen `original-NNN.bin` und erscheinen nicht als Musikdateien. `repair.json` enthält Originalpfade, Hashes, Metadatenänderungen, Quellen, Methode, Zustände, Fehler und Zeitpunkte.

Persistente Zustände umfassen AWAITING_APPROVAL, APPROVED, BACKUP_CREATED, REPAIR_RUNNING, VALIDATING, COMMITTING, COMMITTED, FAILED, ROLLED_BACK, ROLLBACK_REQUIRED, RESTORE_RUNNING, RESTORE_FAILED und RESTORED. Scans speichern pro Datei einen Checkpoint. Ein Abbruch beendet laufende Werkzeuge; ein Dateiaustausch wird nicht mitten in seiner Validierung abgebrochen. Aufträge lassen sich nach erneutem Scan für die verbleibenden Dateien neu planen und müssen wieder freigegeben werden. Begonnene Dateireparaturen werden nicht blind wiederholt.

Unter **Backup & Restore** eine oder mehrere Reparaturen auswählen. Die Vorschau prüft Backuphashes und die aktuellen Dateien. Nachträgliche, nicht zum Reparaturjournal passende Änderungen sperren das automatische Zurücksetzen. Nach der eigenen Freigabe werden Originale wiederhergestellt, neu angelegte Begleitdateien entfernt und die Originalhashes kontrolliert. Ein unterbrochener Commit kann mit seinen protokollierten Vorher-/Nachher-Zuständen gezielt geprüft werden. Bei einem unklaren Zustand wird nicht überschrieben. Originalbackups bleiben erhalten.

Scan- und Reparaturberichte lassen sich als JSON und CSV exportieren. Der Report enthält keine vollständigen Uploadbeschreibungen oder beliebige private JSON-Zusatzfelder. Bekannte Zugangsdatenfelder und sensible URL-Parameter werden im Audit maskiert. Vollständige Originaldateien im Backup bleiben als Wiederherstellungsbestand unverändert.

## Neue Download-Abschlussprüfung

Der bestätigte Downloadauftrag liefert Interpret und Titel. Die vorhandene yt-dlp-Auswahl lädt weiterhin bevorzugt verfügbares Opus/AAC-Audio. Vor Veröffentlichung werden beide Pflicht-Tags im Container und gegebenenfalls Audiostream gesetzt, die kodierten Audiohashes und Streamparameter verglichen, das Audio vollständig dekodiert und das Cover geprüft. info.json bleibt unverändert. Das PK-JSON wird mit nachvollziehbaren Quellen erstellt. Erst nach erneuter Prüfung des fertigen Ordners wird der Download archiviert. Ein nach einem Absturz bereits veröffentlichter Ordner wird vor der Archivierung ebenfalls geprüft. Alte fehlerhafte Originaldateien werden durch diesen Wiederanlauf nicht stillschweigend repariert.

## Validierung und offene Ausbaustufen

- Automatisierte Tests verwenden selbst erzeugte kurze Audiodateien und einen isolierten Ordner unter `work/`. Opus und AAC/M4A, eingebettetes Cover, manuell gewähltes Cover, Byte-genaue Wiederherstellung, JSON-Erhalt, fehlende und gesperrte Dateien, beschädigtes Audio/JSON, geänderte Quelldaten, Hash-Abweichungen, ein Fehler nach dem Austausch, ein unterbrochener Commit, Freigaben und Argumentquotierung werden geprüft.
- Die tatsächliche GUI-Steuerung wird mit Hintergrund-Runspaces getestet. Browserprüfungen decken Navigation, reale Kennzahlen, Editor, Quellen, Freigaben, Abbruch und schmale Dialoge ab. Die bestehenden Tests für Sammlung, Player, Metadaten, Mehrfachaktionen und Sicherung bleiben relevant.
- Ausführen mit `build/Test-Health.ps1 -FFmpeg <absoluter Pfad> -Probe <absoluter Pfad>`. Für CI ist `-DownloadTools` mit der gleichen festen FFmpeg-Version und SHA-256 wie im Installer vorgesehen. Der Windows-Workflow führt diese Tests vor dem Artefakt-Upload aus.
- Die echte Sammlung wurde ausschließlich lesend geprüft. Parallel beobachtete Änderungen außerhalb dieses Entwicklungslaufs machen frühere Zahlen zu Momentaufnahmen. Ein Scan ist kein Auftrag zur Massenreparatur. Es wurde keine produktive Reparatur dieses Moduls ausgeführt.
- Noch offen sind weitere schreibend freizugebende Audioformate, neues Einbetten von Covern, akustisches Fingerprinting, automatische Dateiumbenennung sowie automatisierte externe DJ-/Mobilplayer-Integration. Der bestehende MusicBrainz-Dialog bleibt getrennt verfügbar; der Health Resolver ruft keine kostenpflichtigen Anbieter auf.
- VirtualDJ und Poweramp werden nicht automatisiert gesteuert. Reload Tags bei Kollektiv Ost – Smak und die anschließende Anzeige in beiden externen Programmen bleiben auf dem jeweiligen Gerät praktisch zu bestätigen. Der Health-Bereich gibt eine manuelle Anleitung und listet Dateien mit vorhandenen Tags, ohne ein veraltetes Datenbankfeld als bewiesenen Defekt auszugeben. Cues, Beatgrids und Datenbanken werden nicht angefasst.
- Für Netzwerkfreigaben ist die schreibende Reparatur gesperrt. Der Feature-Branch führt auch die bereits vor diesem Auftrag vorhandenen Sammlungsmodule mit, die für den aktuellen Desktopstand erforderlich sind. Die veröffentlichte README wurde abgeglichen. Dieser Entwicklungsstand wird nicht automatisch auf den produktiven Hauptbranch übernommen.

## Geprüfte technische Referenzen

- [FFmpeg: Stream Copy, Mapping und Metadaten](https://ffmpeg.org/ffmpeg.html)
- [FFprobe: Stream- und Container-Tags](https://ffmpeg.org/ffprobe.html)
- [FFmpeg: Streamhash-Muxer und Container](https://ffmpeg.org/ffmpeg-formats.html)
- [yt-dlp: Download- und Nachbearbeitungsoptionen](https://github.com/yt-dlp/yt-dlp)
- [VirtualDJ: Reload Tags in der offiziellen Ordnerdokumentation](https://virtualdj.com/manuals/virtualdj/interface/database/smartfolders.html)
- [VirtualDJ-Support: einzelne Dateien im Tag Editor prüfen](https://virtualdj.com/forums/251496/VirtualDJ_Technical_Support/Reload_Tags.html)
