# Prüfbericht: verständliche Bibliothekspflege

Datum: 25. November 2026. Funktionsprüfung für die Änderungen auf `codex/library-health-center`, Basis 0.5.1. Die anschließende Paketierung und Veröffentlichung als 0.5.2 wurde separat beauftragt; siehe [Versionshinweise](RELEASE-0.5.2.md).

## Scanstart: reproduzierte Ursache

Eine isolierte Kopie der vollständigen Windows-App wurde mit eigenen Einstellungen und Testmusik gestartet. Über die eingebettete WebView2-Oberfläche wurden die normalen Schaltflächen Bibliothekspflege und Vollscan betätigt. Die native Nachrichtenwarteschlange, der Controller und seine echten Hintergrund-Runspaces waren aktiv; die Nachrichtenbrücke wurde nicht ersetzt.

Der ursprüngliche Scanstart scheiterte vor dem Hintergrundauftrag an den automatisch gewählten Arbeits-/Sicherungspfaden unter dem umgeleiteten Dokumenteordner `%USERPROFILE%\OneDrive\Documents`. `Assert-SafePath` erkannte dort eine Verknüpfung. Sichtbare Originalmeldung: „Der Pfad enthält eine Verknüpfung“, gefolgt vom Dokumentepfad. Neue Standardordner liegen deshalb lokal unter `SetArchiv`; gespeicherte eigene Pfade werden beibehalten. Ungültige Pfade ergeben eine verständliche Meldung samt Diagnose. Die Pfadsperre wurde nicht entfernt.

## Native Windows-Abnahme

Testkopie: `work/native-health-20261125`, getrennte Konfiguration in `desktop-local`. Testmusik: drei kurze Opus-Tracks, ein einstündiges Opus-Set und eine absichtlich beschädigte Opus-Datei. Ein Track hatte fehlende Angaben und passende Quelldaten, ein anderer widersprüchliche Quellen. Zwei Tracks hatten identische Audiodaten. Reparaturen und Rücknahmen betrafen ausschließlich diese Testkopie.

| Prüfung | Ergebnis |
| --- | --- |
| Sofortmeldung und tatsächlicher Start | „Prüfung wird vorbereitet …“ unmittelbar sichtbar; danach echte Runspace-Meldungen und fünf Ergebnisdateien. |
| Mehrfachklick | Startschaltfläche sofort gesperrt; nur eine native Startbestätigung pro Scan. |
| Dateisuche und Prüfschritte | Native Phasenmeldungen, aktuelle Datei und Gesamtzahl werden übertragen. Unbekannte Gesamtzahl bleibt unbestimmt. |
| Langes Set / Tiefenscan | Messbarer Dateifortschritt aus FFmpeg-Audiodauer zwischen 0 und 100 Prozent nachgewiesen. Keine erfundene Restzeit. |
| Abbruch / Fortsetzen | Abbruch während der langen Dekodierung; CANCELLED mit Teilergebnissen. Fortsetzen über normale Schaltfläche beendet den Scan. |
| Einfach / Erweitert | Wechsel vor, während und nach Scans; Fortschritt und Dateiauswahl bleiben erhalten. |
| Tatsächlicher App-Neustart | Gespeichertes „Erweitert“, fünf Berichtsdateien, letzte Prüfzeit und drei vorhandene Reparatursicherungen nach Neustart wieder geladen. Anschließender Vollscan erneut gestartet und abgeschlossen. |
| Änderungsprüfung | Quelldatei gezielt geändert. Der betroffene Datensatz bekam eine neue Prüfzeit; das unveränderte lange Set behielt seine vorhandene Prüfzeit. |
| Geführte Reparatur | Fehlende Angaben über einfache Ergebnisliste, echten Quelleneditor und Reparaturvorschau ergänzt. Ausführung erst nach eigenem Freigabekästchen. |
| Sicherung / Rücknahme | Original im Sicherungsbereich ausgewählt, eigene Wiederherstellungsvorschau freigegeben; SHA-256 des Originals nach Rücknahme identisch. |
| Beschädigte Audiodatei | Genau eine Testdatei als Audiofehler ausgewiesen. |
| Fehlendes Prüfprogramm | Startfehler mit nächster Aktion und technischen Details; Oberfläche wieder bereit. |
| Unerreichbarer Musikordner | Verständliche Aufforderung, einen erreichbaren Musikordner zu wählen. |
| Leerer Ordner | „Keine unterstützten Musikdateien gefunden“. |

Wiederholbarer nativer Prüflauf: `build/tests/Health.Native.UI.cjs <debug-port> <fixture-base>`. Er verbindet sich nur mit einer ausdrücklich gestarteten vollständigen App, prüft die Testpfade unter `work/` und verwendet keine nachgebaute Nachrichtenbrücke. Die gezielten Teständerungen bleiben in der Fixture. Die Fenster wurden vom Desktop-Helfer nicht angeboten; deshalb erfolgte die Bedienprüfung über den lokalen Debuganschluss der tatsächlich laufenden WinForms/WebView2-App.

Lokale Nachweise liegen in `work/native-health-20261125`: ursprünglicher Screenshot `before.png`, native Abschlussansicht `native-final.png`, native Meldungen `native-evidence.json`, gespeicherte Berichte und Reparaturjournale in der getrennten Konfiguration. Diese Testdaten werden nicht veröffentlicht.

## Ergänzende Regressionen

- `build/Test-Health.ps1 -FFmpeg D:/YT-DLP/bin/ffmpeg.exe -Probe D:/YT-DLP/bin/ffprobe.exe -SkipUI`: bestanden, einschließlich Scan, Quellen, Audiohash, vollständiger Dekodierung, Originalbackups, exakter Rücknahme, Konflikt-/Unicodefällen, VirtualDJ-DOM-Schutz, MP3-Covern und Quarantäne.
- `Health.Web.Tests.ps1`: echte Hintergrund-Runspaces, Freigabeprüfung und Wiederherstellung bestanden; zusätzlich gespeicherte Ansicht, Pfade, Bericht, erneuter-Prüfungs-Marker und verständlicher Fehler bei fehlendem Prüfprogramm geprüft.
- `Health.UI.cjs`: einfache Liste, Modusschalter, gemeinsamer laufender Dateifortschritt, Auswahl, Quelleneditor, gesperrte ungeprüfte Freigabe und schmale Dialoge bestanden.
- `Health02.UI.cjs`: vorhandene erweiterte Datenbank-, Cover-, Quarantäne- und Wiederherstellungsoberfläche bestanden.

Die ergänzenden Browser- und Controllerprüfungen ersetzen die oben beschriebene native Abnahme nicht. Produktive Musik, die aktive VirtualDJ-Datenbank und externe Konten wurden für diesen Auftrag nicht verändert.
