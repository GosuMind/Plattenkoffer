# Plattenkoffer

Windows-App von Mindgamer zum Sammeln, Organisieren und Anhören von Tracks und DJ-Sets. Die Vorschau lässt Künstler, Titel und Typ korrigieren. In der Bibliothek kannst du Aufnahmen suchen, abspielen, verschieben und als MP3 exportieren.

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
