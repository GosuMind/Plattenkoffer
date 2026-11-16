# Plattenkoffer

Windows-App von Mindgamer zum Sammeln, Organisieren und Anhören von Tracks und DJ-Sets. Die Vorschau lässt Künstler, Titel und Typ korrigieren. In der Bibliothek kannst du Aufnahmen suchen, abspielen, verschieben und als MP3 exportieren.

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
