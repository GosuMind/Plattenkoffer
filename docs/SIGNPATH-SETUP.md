# SignPath-Anbindung

Nach der Zusage in SignPath das Projekt mit dem GitHub-Repository und GitHub
Actions als Trusted Build System verbinden. Eine Artefaktkonfiguration für die
Plattenkoffer-Setup-EXE und eine Release-Policy mit manueller Freigabe einrichten.
Die Artefaktregeln sollen den Produktnamen Plattenkoffer und die Release-Version
prüfen. Der SignPath-Freigebende vergleicht die Anfrage mit dem Build auf main.

In GitHub das Environment signpath-release anlegen und dort hinterlegen:

- Secret: SIGNPATH_API_TOKEN (Token des SignPath-Build-Benutzers).
- Variablen: SIGNPATH_ORGANIZATION_ID, SIGNPATH_PROJECT_SLUG,
  SIGNPATH_SIGNING_POLICY_SLUG, SIGNPATH_ARTIFACT_CONFIGURATION_SLUG.

Unter Actions den Workflow Sign Windows installer auf main manuell auslösen.
Die Anfrage in SignPath freigeben. Der Workflow wartet bis zu einer Stunde auf
das Ergebnis. Nach erfolgreicher Signaturprüfung steht das Artefakt
Plattenkoffer-Windows-Signed mit EXE und neuer SHA256SUMS.txt bereit.
Für den Release die Anleitung mit der neuen Prüfsumme aktualisieren und die
geprüfte EXE mit den Lizenzhinweisen packen. Der Workflow veröffentlicht keinen
Release und die normalen Windows-Builds laufen weiterhin separat.

Offizielle Integration:
https://github.com/SignPath/github-action-submit-signing-request
