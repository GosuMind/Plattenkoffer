# Plattenkoffer für Android

Konzeptstand vom 16. November 2026

**Status:** Für später vorgemerkt. Die Umsetzung ist noch nicht begonnen.

## Ziel und Umfang der ersten Version

Plattenkoffer für Android ist ein eigenständiger Offline-Player für lokale Tracks und DJ-Sets. Nutzer können vorhandene Audiodateien auf dem Handy aufnehmen und abspielen. Die Windows-App und das Handy können ausgewählte Aufnahmen in beide Richtungen kopieren, wenn beide im selben WLAN sind. Unterwegs spielt das Handy seine lokalen Kopien auch im Flugmodus und bei ausgeschaltetem PC ab.

Der erste Anwendungsfall ist eine bewusst zusammengestellte Auswahl für unterwegs. Kopien auf PC und Handy gehören jeweils zur lokalen Sammlung des Geräts. Die erste Version plant weder automatische Synchronisation noch Fernzugriff über das Internet, Cloud-Speicher, Nutzerkonten oder eine iPhone-App. Die Audioquelle ist eine Datei, die dem sendenden Gerät bereits vorliegt. Ein YouTube-Link allein lässt sich auf Android dadurch noch nicht offline anhören.

## Vom PC aufs Handy

1. In der Windows-Sammlung ein oder mehrere Sets und Tracks auswählen und **Ans Handy senden** öffnen.
2. Beim ersten Transfer auf Android **Geräte verbinden** wählen und den QR-Code scannen, den Windows anzeigt. Die Kopplung stellt sicher, dass der Auftrag dem vorgesehenen Gerät zugeordnet ist.
3. Auf dem Handy den Eingang prüfen. Die Ansicht zeigt die ausgewählten Einträge, ihre Gesamtgröße, den verfügbaren Platz und bereits vorhandene Dateien.
4. **Übernehmen** startet den Transfer. Die Oberfläche zeigt Fortschritt pro Auftrag und macht sichtbar, welche Einträge angekommen sind. Nach Abschluss erscheinen sie in **Auf dem Handy**.

Ein mehrteiliges Set bleibt ein Sammlungseintrag. Die Audiodateien werden in der vorhandenen Teilreihenfolge übertragen. Metadaten und vorhandene Cover werden mitkopiert. Wenn ein Teil fehlt oder ein Transfer abbricht, erscheint die unvollständige Version nicht als abspielbares Set.

## Auf Android importieren und offline hören

**Dateien hinzufügen** öffnet die Android-Dateiauswahl. Nutzer können vorhandene Audiodateien in die lokale App-Sammlung übernehmen und dort manuell einordnen. Die Oberfläche übernimmt die Gestaltung und Begriffe der Windows-App. Die mobile Navigation bietet **Sammlung**, **Sets** und **Tracks**, eine Suche und einen kompakten Player.

Die Wiedergabe funktioniert im Hintergrund. Über den Sperrbildschirm oder die Mediensteuerung können Nutzer pausieren und fortsetzen. Bei langen Aufnahmen speichert PK die Wiedergabeposition pro Eintrag. Bei mehrteiligen Sets gehören Teil und Position zusammen. Auch nach App-Neustart und nach Wiedergabe eines anderen Tracks soll das Set an seiner letzten Stelle fortgesetzt werden können.

## Vom Handy zurück auf den PC

1. Auf Android eine vorhandene Datei über **Dateien hinzufügen** aufnehmen oder einen bereits gespeicherten Eintrag auswählen.
2. Bei Bedarf Angaben manuell ergänzen und **An PC senden** wählen.
3. Auf Windows den Eingang mit Dateigröße, Einordnung und möglichen Duplikaten prüfen.
4. Die Übernahme bestätigen. PK legt die angenommene Kopie in der Windows-Sammlung ab und erhält die übertragenen Angaben. Die Kopie auf dem Handy bleibt unabhängig davon verfügbar.

## Angaben und Dateiformate

| Eintrag | Gemeinsam übertragene Angaben |
| --- | --- |
| Track | Tracktitel, Künstler, optional Album und Erscheinungsjahr, vorhandenes Cover |
| Set | DJ, optional Set-Reihe, Veranstaltung, Location, Aufnahmedatum oder Jahr, eigener Set-Name, vorhandenes Cover und Teilreihenfolge |

Die App bildet den angezeigten Set-Namen nach derselben Regel wie Windows. Ein eigener Set-Name hat Vorrang. Andernfalls entsteht er aus DJ, Veranstaltung oder Location und Datum oder Jahr. Tracktitel und die Dateinamen der übertragenen Originale werden dadurch nicht geändert. Für den ersten Transfer ist eine unveränderte Dateikopie vorgesehen. Welche Audioformate Android direkt abspielen kann und wie PK bei inkompatiblen Dateien reagiert, wird vor der Implementierung anhand des gewählten Players geprüft.

## Kopieren, Speicherplatz und Duplikate

- Eine Aktion kopiert nur die ausgewählten Aufnahmen. Entfernt man eine Kopie vom Handy, bleibt die PC-Kopie erhalten.
- Der Empfänger prüft den verfügbaren Speicher vor dem Start. Bei Platzmangel kann der Nutzer die Auswahl verkleinern.
- Ein identischer Dateiname allein beweist kein Duplikat. Die Prüfung soll Dateiinhalte vergleichen und bei unterschiedlichen Aufnahmen mit gleichem Namen beide erhalten können.
- Empfangene Daten werden zunächst temporär abgelegt. Ein Eintrag wird erst nach vollständiger Übertragung und Integritätsprüfung in die Sammlung übernommen.
- Bei abgebrochener Verbindung bleibt der Originalbestand erhalten. Der Empfänger zeigt den Abbruch an und bietet einen erneuten Versand an. Ob Teilübertragungen später fortgesetzt werden können, wird bei der technischen Planung entschieden.

## Lokale Verbindung und offene Entscheidungen

Die Kopplung soll eine zeitlich begrenzte, nur einmal verwendbare Bestätigung nutzen. Ein Transfer braucht einen bestätigten Empfänger. Plattenkoffer soll weder beliebige Dateien im Heimnetz freigeben noch ohne Zustimmung eingehende Dateien in die Sammlung aufnehmen. Der QR-Code soll nur die notwendigen Verbindungsinformationen enthalten. Das konkrete Übertragungsprotokoll, die Absicherung gegen andere Teilnehmer im WLAN und die Behandlung der Windows-Firewall sind vor der Umsetzung zu entscheiden.

Weitere offene Punkte sind die Android-Mindestversion, der Medienplayer, das Ablageverzeichnis auf dem Handy, der Umgang mit externen Speichermedien und die Frage, ob vertraute Geräte zwischen Sitzungen gespeichert werden sollen. Wiedergabepositionen bleiben in der ersten Version auf dem jeweiligen Gerät. Ein geräteübergreifender Abgleich kann später geplant werden.

## Erster Abnahmetest

1. Ein zweiteiliges Set und zwei Tracks in Windows auswählen, Android und PC koppeln und den Empfang auf dem Handy bestätigen.
2. Prüfen, dass das Set als einzelner Eintrag erscheint, beide Teile in der richtigen Reihenfolge abspielt und Metadaten sowie Cover mitgekommen sind.
3. Flugmodus aktivieren und den PC ausschalten. Einen Track und das Set offline abspielen. Das Set über den Sperrbildschirm pausieren, einen anderen Track hören und anschließend nach App-Neustart an der gespeicherten Stelle fortsetzen.
4. Eine bereits auf Android vorhandene Datei importieren, einordnen und nach Wiederherstellen der WLAN-Verbindung an den PC senden. Dort den Eingang bestätigen und Datei sowie Einordnung prüfen.
5. Einen identischen Eintrag erneut senden und die Duplikatmeldung prüfen. Einen Transfer unterbrechen und sicherstellen, dass kein unvollständiger Eintrag abspielbar erscheint.
6. Die Handy-Kopie eines übertragenen Tracks entfernen. Prüfen, dass der PC die Originalaufnahme weiterhin findet und abspielt.
