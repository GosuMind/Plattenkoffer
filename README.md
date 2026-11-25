# Plattenkoffer

Plattenkoffer ist eine kostenlose Open-Source-App für Windows zum Organisieren und Anhören deiner Musiksammlung. Verwalte Tracks und DJ-Sets mit Coverbildern, Genres und Metadaten, erstelle Playlisten und markiere deine Favoriten. Ein Mini-Player und anpassbare Ansichten begleiten dich beim Hören.

Du kannst vorhandene Audiodateien importieren, unterstützte Formate umwandeln und Inhalte über YouTube-Links herunterladen, soweit dies rechtlich und nach den geltenden Plattformbedingungen zulässig ist.

## Verantwortungsvoll nutzen

Plattenkoffer ist ausschließlich für rechtmäßige Nutzung vorgesehen. Lade, kopiere, konvertiere oder teile Inhalte nur, wenn du dazu berechtigt bist – beispielsweise aufgrund eigener Rechte, einer entsprechenden Erlaubnis oder einer gesetzlichen Erlaubnis.

Beachte das geltende Urheberrecht, die Lizenzbedingungen der Inhalte und die Nutzungsbedingungen der jeweiligen Plattform. Nutze Plattenkoffer nicht für unbefugte Downloads, rechtswidrige Weitergabe oder die unzulässige Umgehung wirksamer technischer Schutzmaßnahmen.

Du bist dafür verantwortlich, die erforderlichen Berechtigungen für deine jeweilige Nutzung zu prüfen. Plattenkoffer räumt dir keine Rechte an fremden Musikstücken, Aufnahmen oder Videos ein.

Plattenkoffer wird unabhängig entwickelt und steht in keiner Verbindung zu YouTube oder Google.

## Kostenlos und Open Source

Die Nutzung von Plattenkoffer ist kostenlos. Wenn du die Weiterentwicklung unterstützen möchtest, kannst du freiwillig [über Ko-fi](https://ko-fi.com/mindgamer49330) beitragen.

Die beschriebenen Funktionen beziehen sich auf Version 0.5.2. Die Sammlung verwendet das bestehende Design mit kompakter Filterauswahl, sichtbaren aktiven Filtern, Coverkarten, rechter Detailansicht und durchgehendem Player. Unter **Ansicht** lassen sich Kachelgröße und die Auswahl aller sichtbaren Titel öffnen. Bei ausgewählten Titeln erscheinen die bisherigen Mehrfachaktionen.

Version **0.5.2** macht die Bibliothekspflege über **Einfach / Erweitert** zugänglich. Sofortige Startbestätigung, verständliche Ergebnisgruppen, gemeinsame Dateiauswahl und geführte Reparaturen ergänzen den bisherigen Funktionsumfang. Lange Tiefenscans zeigen messbaren Dateifortschritt; Abbruch, Fortsetzen und die Prüfung geänderter Dateien bleiben verfügbar. Automatisch gewählte lokale Arbeitsordner beheben den Scanstartfehler bei umgeleiteten OneDrive-Dokumenteordnern. Play und Pause sitzen mittig im orangefarbenen Kreis; die Wiedergabesymbole erhalten Lichtkanten und Schatten. [Bedienungsanleitung](docs/BIBLIOTHEKSPFLEGE-BEDIENUNG.md) · [Versionshinweise](docs/RELEASE-0.5.2.md)

**Bibliothekspflege** ergänzt einen lesenden Bibliotheksscan, Quellenvergleich, Cover- und Duplikatdiagnose sowie freigabepflichtige Einzel- und Stapelreparaturen. Vor jeder Änderung werden vollständige Originalbackups verifiziert. Opus/Ogg und AAC/M4A lassen sich ohne Audiokodierung bearbeiten; weitere Formate bleiben zunächst nur lesend. Audiohash, Streamparameter und geschriebene Tags werden geprüft, Originalpfade bleiben erhalten. Neue Downloads erhalten verbindliche Tags und PK-JSON samt Abschlussprüfung. Bedienung, Wiederherstellung und Einschränkungen stehen in [Library Health](docs/LIBRARY-HEALTH.md).

Version 0.5.1 ergänzt semantische Metadatenprüfung und Unicode/NFC, VirtualDJ-2026-Datenbankkorrekturen mit vollständigem XML-Inhaltsvergleich, MP3-JPEG-Covereinbettung ohne Audiokodierung sowie verifizierte Duplikatquarantäne. Jede Datenbankänderung und Archivierung benötigt eine eigene Vorschau und Freigabe. [Umfang, technische Grenzen und Rückgängig-Anleitung](docs/LIBRARY-HEALTH-02.md)


KI-gestützte Einordnung und Track-Erkennung sind für später vorgemerkt. Der aktuelle Funktionsumfang benötigt dafür keine kostenpflichtigen Dienste. [Planungsstand und offene Punkte](docs/TRACK-ERKENNUNG.md)

## Version 0.3

Die Sammlung verwendet die Oberfläche des klickbaren Entwurfs mit Cover- und Listenansicht, Navigation und festem Player. Über **Hinzufügen** stehen YouTube-Suche und Linkvorschau sowie der Import vorhandener Dateien und Ordner zur Verfügung. Die Windows-App stellt die Oberfläche lokal mit Microsoft Edge WebView2 dar. Setup installiert die Runtime bei Bedarf.

## Version 0.2

Mit Version 0.2 bekommt die Windows-App den YouTube-Mehrfachimport, Filter für DJ, Set-Reihe, Veranstaltung und Location sowie die Möglichkeit, vorhandene Musik am bisherigen Speicherort in die Bibliothek aufzunehmen. Die Versionsnummer steht in der Titelleiste und unter **Einstellungen → Über Plattenkoffer**. Die Update-Suche verwendet GitHub Releases. Die automatische Installation setzt ein signiertes Setup und ein hinterlegtes Herausgeberzertifikat voraus.

App und Installer verwenden dieselbe Versionsnummer. Die letzte Stelle läuft von 0 bis 9. Auf `0.2.9` folgt `0.3.0`. Beim nächsten Übertrag folgt auf `0.9.9` die Version `1.0.0`.

## Android-Ausblick

Eine Android-App für lokale Dateikopien zwischen PC und Handy und Offline-Wiedergabe ist für später geplant. [Konzept und Abnahmeszenario](docs/ANDROID-KONZEPT.md)

## Installation

Windows 10 oder 11 (x64), Internetzugang und ein beschreibbarer Programmordner genügen. Starte die Setup.exe, wähle den Installationsordner und bei Bedarf das Desktop-Symbol. Das Setup bezieht yt-dlp, FFmpeg und Deno von den Anbietern und prüft die Paket-Hashes. Öffne danach unter **Einstellungen** den Dialog zur Wahl des Musikordners.

Bei einem Update zuerst über **Einstellungen → Konfiguration sichern …** ein ZIP speichern und dann die App schließen. Die Konfiguration liegt unter `%LOCALAPPDATA%\SetArchiv`. Die Deinstallation läuft über **Installierte Apps**. Die Musikbibliothek und Konfiguration liegen getrennt vom Programmordner.

Die Sicherung enthält auch Playlisten, Favoriten, Fortsetzungspositionen sowie Tracklisten, eigene Cover und PK-Metadaten aus verwalteten Musikordnern. Audiodateien sind nicht enthalten und müssen separat gesichert werden. Beim Wiederherstellen werden enthaltene Sammlungsdaten in den im ZIP gespeicherten Musikordner zurückgeschrieben; vorhandene Dateien werden überschrieben. Zusätzliche Cover und Tracklisten, die nicht im ZIP stehen, bleiben erhalten. Alte Konfigurations-ZIPs bleiben lesbar und lassen die neu hinzugekommenen Daten unverändert. Vor jeder Wiederherstellung wird automatisch ein Sicherungs-ZIP angelegt. Bei Schreibfehlern werden bereits geänderte Dateien zurückgesetzt.

## Windows-Build

Führe in PowerShell im Projektordner aus:

```powershell
./build/Build-Windows.ps1
```

Das Skript lädt Inno Setup 6.7.4, prüft SHA-256 und baut den Installer unter `release/` mit `SHA256SUMS.txt`. Eine vorhandene Installation lässt sich mit `-Compiler <Pfad zur ISCC.exe>` verwenden. GitHub Actions stellt EXE und Prüfsumme als Build-Artefakt bereit.

## Lizenz und Signierung

Der eigene Code steht unter der [MIT-Lizenz](LICENSE). Hinweise zu den Drittprogrammen stehen unter [Lizenzen](setup/Lizenzen/Drittanbieter.txt).

Der lokale Entwurf ist unsigniert. Der geplante Weg über [SignPath Foundation](https://signpath.org/terms) setzt ein veröffentlichtes Projekt, nachvollziehbare Builds und die Aufnahme durch SignPath voraus. Danach wird die Signierung als separater Release-Schritt eingerichtet und jede signierte EXE mit neu berechneter Prüfsumme veröffentlicht.


## Code signing policy

[Signierregeln, Verantwortliche und Datenschutz](docs/CODE-SIGNING.md).
