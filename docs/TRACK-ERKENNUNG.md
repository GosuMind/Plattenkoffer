# Track-Erkennung in Plattenkoffer

## Status vom 16. November 2026

Die Einführung von KI und Track-Erkennung ist zurückgestellt. Plattenkoffer wird vorerst mit lokalen Funktionen weiterentwickelt. Dazu gehören Import, manuelle Einordnung, Sammlung, Wiedergabe und Export.

Für den zurückgestellten Funktionsumfang werden vorerst kein ACRCloud-Projekt angelegt, kein Hetzner-Server bestellt und keine kostenpflichtigen APIs aktiviert. Der Browser-Entwurf verwendet vorbereitete Beispiele für Metadaten und einen simulierten Track-Treffer. Beides dient ausschließlich der Erprobung des Ablaufs.

Für eine spätere Wiederaufnahme liegen die lokale Ausschnittlogik in `setup/DJ-Sets-Recognition.ps1` und ein Entwurf des Erkennungsdienstes unter `recognition-service/` vor. Der Dienst wurde nicht bereitgestellt. Ein Live-Test mit ACRCloud und die Integration in die Windows-App stehen aus. Für die Stelle bei 39:08 im HÖR-Set liegt kein verifizierter Treffer vor.

## Geplante KI-Einordnung

PK könnte künftig Titel und Beschreibung öffentlicher YouTube-Videos abrufen und daraus DJs, Set-Reihe, Veranstaltung und Location vorschlagen. Nutzer prüfen und korrigieren die Angaben vor der Übernahme. Offene Felder bleiben leer. Die bestätigten Angaben bleiben lokal in der Sammlung und können jederzeit manuell bearbeitet werden.

Als spätere Beta-Option sind manuell vergebene Kontingente vorgesehen. Importpakete und ein mögliches Abo bleiben Ideen. Preise, Anbieterzugänge, Hosting und Abrechnung werden erst bei einer Wiederaufnahme entschieden.

Die folgenden Abschnitte beschreiben den geplanten Funktionsumfang.

## Ablauf in der Windows-App

- **Track erkennen** prüft eine einzelne Aufnahme. **Track hier erkennen** prüft einen Ausschnitt um die aktuelle Wiedergabeposition eines Sets.
- **Set analysieren** prüft Ausschnitte über die gesamte Dauer. Vor dem Start zeigt PK das benötigte Kontingent. Während der Analyse zeigt PK Fortschritt und bietet einen Abbruch an.
- Ergebnisse erscheinen als Vorschläge mit Position im Set. Übereinstimmende Treffer aus benachbarten Proben werden gruppiert. Unbekannte Stellen bleiben sichtbar. Die Zeit einer Probe ist ein Anhaltspunkt für die Wiedergabe. Ein genauer Trackbeginn braucht zusätzliche Belege.
- Nutzer übernehmen, ändern oder verwerfen Vorschläge. Bestätigte Track-IDs bleiben lokal am zugehörigen Set und lassen sich auch ohne aktives Kontingent öffnen.

## Dienst und Abrechnung

PK erstellt kurze Ausschnitte aus einer lokal verfügbaren Aufnahme. Der PK-Dienst authentifiziert den Nutzer, prüft die Freischaltung und gibt die Ausschnitte an den Erkennungsanbieter weiter. Anbieterschlüssel liegen beim Dienst. Ein YouTube-Link allein liefert der Windows-App noch keine Audiodatei für die Erkennung.

Ein Einzelaufruf und eine Set-Analyse erhalten je eine eigene Auftrags-ID. Bei einem erneuten Abruf derselben ID liefert der Dienst den bestehenden Auftrag. Vor einer Set-Analyse reserviert er das benötigte Kontingent. Nach Abschluss oder Abbruch rechnet er nach der vereinbarten Regel ab und gibt die übrige Reservierung frei. Preise, Paketgrößen und der Umgang mit erfolglosen Erkennungen sind offen. Die erste Beta kann über manuell freigeschaltete Kontingente laufen.

## Umsetzung und Abnahme

1. Lokale Ausschnitte erzeugen und die drei Aufrufarten an der Windows-Bibliothek anbinden.
2. Den Erkennungsdienst nach Anbieterentscheidung integrieren. Mit bekannten Tracks sowie Sets mit Übergängen und unbekannten IDs testen. Anbieterfehler und Stellen ohne Treffer separat behandeln.
3. Kontingente und Auftragszustand im Dienst dauerhaft speichern. Gleichzeitige Aufträge, Wiederholungen, Abbruch und Teilergebnisse testen.
4. Treffer in der Bibliothek prüfen und speichern. Die Zuordnung nach Neustart und bei abgelaufenem Kontingent testen.
5. Einen bekannten Track und das HÖR-Set um 39:08 mit einer verfügbaren Audiodatei testen. Für die Set-Erkennung Ergebnisse mit einer Trackliste vergleichen und Lücken dokumentieren.
