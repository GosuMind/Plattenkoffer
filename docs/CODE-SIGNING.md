# Code signing policy

Plattenkoffer 0.1.13 wird als unsignierter Windows-Installer veröffentlicht.
Für künftige Releases ist eine Signierung über SignPath Foundation vorgesehen.

## Verantwortliche

- Entwicklung und Code-Review: Mindgamer ([GosuMind](https://github.com/GosuMind)).
- Freigabe von Signieranfragen: Mindgamer. Jede Anfrage wird anhand des
  Release-Tags, des Build-Laufs und der erwarteten EXE manuell geprüft.

## Signierte Dateien und Build

Der Windows-Installer wird mit GitHub Actions aus dem Projektquellcode gebaut.
Signiert werden soll die von diesem Build erzeugte Plattenkoffer-Setup.exe.
Die separat bezogenen Programme yt-dlp, FFmpeg und Deno behalten ihre eigenen
Herstellerdateien. Die Prüfsumme im veröffentlichten Paket wird nach dem
Signieren aus der fertigen EXE berechnet.

## Datenschutz

- Bei Installation und bei manuell gestarteten Werkzeug-Updates verbindet
  sich Plattenkoffer mit GitHub und Gyan, um die Werkzeugpakete zu beziehen.
- Beim Laden der Vorschau oder beim Download verarbeitet yt-dlp den gewählten
  YouTube-Link und kommuniziert mit YouTube und dessen Medienservern.
- Der Ko-fi-Link öffnet auf Klick die öffentliche Unterstützungsseite im Browser.
- Einstellungen, Downloadarchiv, Warteschlange und Fehlerlogs liegen lokal.
  Über die Diagnose können Nutzer Fehlerdetails selbst in die Zwischenablage kopieren.

Datenschutzinformationen der Dienste:
[GitHub](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement),
[Google/YouTube](https://policies.google.com/privacy),
[Ko-fi](https://more.ko-fi.com/privacy).
Der FFmpeg-Build wird von [Gyan](https://www.gyan.dev/ffmpeg/builds/) bereitgestellt.
