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

Die beschriebenen Funktionen beziehen sich auf den Entwicklungsstand 0.4.7.

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
