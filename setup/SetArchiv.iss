[Setup]
AppId=SetArchiv
AppName=Plattenkoffer
AppPublisher=Mindgamer
SetupIconFile=SetArchiv.ico
UninstallDisplayIcon={app}\SetArchiv.ico
#define AppVersion "0.5.2"
#ifndef UpdateSignerHash
  #define UpdateSignerHash ""
#endif
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}.0
DefaultDirName={localappdata}\Programs\Plattenkoffer
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#ifdef IsolatedTest
CreateUninstallRegKey=no
#endif
ArchitecturesAllowed=x64compatible
MinVersion=10.0
OutputDir=..\release
OutputBaseFilename=Plattenkoffer-Setup-{#AppVersion}
WizardStyle=modern
LicenseFile=Nutzungshinweis.txt
ArchiveExtraction=full

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
WizardLicense=Hinweis zur rechtmäßigen Nutzung
LicenseLabel=Bitte lesen Sie den folgenden Nutzungshinweis vor der Installation.
LicenseLabel3=Bestätigen Sie anschließend, dass Sie den Hinweis gelesen haben und Plattenkoffer rechtmäßig verwenden werden.
LicenseAccepted=Ich habe den Hinweis gelesen und stimme der rechtmäßigen Nutzung &zu.
LicenseNotAccepted=Ich stimme &nicht zu.

[INI]
Filename: "{app}\plattenkoffer.ini"; Section: "Plattenkoffer"; Key: "Version"; String: "{#AppVersion}"; Flags: uninsdeletesection
Filename: "{app}\plattenkoffer.ini"; Section: "Plattenkoffer"; Key: "UpdateSignerHash"; String: "{#UpdateSignerHash}"; Flags: uninsdeletesection

[Tasks]
Name: "desktopicon"; Description: "Desktop-Symbol erstellen"
Name: "migrate"; Description: "Einstellungen und Downloadarchiv aus D:\YT-DLP übernehmen"; Check: HasLegacy

[Files]
Source: "Nutzungshinweis.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "Lizenzen\*"; DestDir: "{app}\Lizenzen"; Flags: ignoreversion
Source: "plattenkoffer-banner.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "SetArchiv.ico"; DestDir: "{app}"; Flags: ignoreversion

Source: "DJ-Sets-*.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "ui\*"; DestDir: "{app}\ui"; Flags: ignoreversion
Source: "..\work\webview2\package\lib\net462\Microsoft.Web.WebView2.Core.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\work\webview2\package\lib\net462\Microsoft.Web.WebView2.WinForms.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\work\webview2\package\runtimes\win-x64\native\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\work\webview2\package\LICENSE.txt"; DestDir: "{app}\Lizenzen"; DestName: "WebView2-LICENSE.txt"; Flags: ignoreversion
Source: "..\work\webview2\package\NOTICE.txt"; DestDir: "{app}\Lizenzen"; DestName: "WebView2-NOTICE.txt"; Flags: ignoreversion
Source: "..\work\webview2\MicrosoftEdgeWebview2Setup.exe"; Flags: dontcopy
Source: "{tmp}\yt\yt-dlp.exe"; DestDir: "{app}"; Flags: external ignoreversion; ExternalSize: 10591079; Check: InstallYt
Source: "{tmp}\yt\_internal\*"; DestDir: "{app}\_internal"; Flags: external recursesubdirs createallsubdirs ignoreversion; ExternalSize: 40000000; Check: InstallYt
Source: "{tmp}\ff\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 105423872; Check: InstallFFmpeg
Source: "{tmp}\ff\ffmpeg-9.0.2-essentials_build\bin\ffprobe.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 105221120; Check: InstallFFmpeg
Source: "{tmp}\ff\ffmpeg-9.0.2-essentials_build\bin\ffplay.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 106903552; Check: InstallFFmpeg
Source: "{tmp}\deno\deno.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 98081568; Check: InstallDeno
Source: "D:\YT-DLP\config\dj-set-gui.json"; DestDir: "{localappdata}\SetArchiv\config"; Tasks: migrate; Flags: external skipifsourcedoesntexist onlyifdoesntexist uninsneveruninstall
Source: "D:\YT-DLP\config\downloaded.txt"; DestDir: "{localappdata}\SetArchiv\config"; Tasks: migrate; Flags: external skipifsourcedoesntexist onlyifdoesntexist uninsneveruninstall
Source: "D:\YT-DLP\config\dj-set-aliases.json"; DestDir: "{localappdata}\SetArchiv\config"; Tasks: migrate; Flags: external skipifsourcedoesntexist onlyifdoesntexist uninsneveruninstall
Source: "LegacyDefaults.json"; DestDir: "{localappdata}\SetArchiv\config"; DestName: "dj-set-gui.json"; Tasks: migrate; Flags: onlyifdoesntexist uninsneveruninstall

#ifndef IsolatedTest
[Icons]
Name: "{userprograms}\Plattenkoffer"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{app}\DJ-Sets-Start.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SetArchiv.ico"
Name: "{userdesktop}\Plattenkoffer"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ""{app}\DJ-Sets-Start.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SetArchiv.ico"; Tasks: desktopicon

#endif
[Code]
var
  NeedYt, NeedFFmpeg, NeedDeno: Boolean;

function UsageAcknowledgementPath: String;
begin
#ifdef IsolatedTest
  Result := ExpandConstant('{app}\nutzungshinweis-bestaetigt.ini');
#else
  Result := ExpandConstant('{localappdata}\SetArchiv\config\nutzungshinweis-bestaetigt.ini');
#endif
end;

function HasUsageAcknowledgement: Boolean;
begin
  Result := GetIniString('Nutzungshinweis', 'Version', '', UsageAcknowledgementPath) = '2026-11-21.1';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and not WizardSilent then begin
    ForceDirectories(ExtractFileDir(UsageAcknowledgementPath));
    if WizardForm.LicenseAcceptedRadio.Checked then begin
      if not SetIniString('Nutzungshinweis', 'Version', '2026-11-21.1', UsageAcknowledgementPath) then
        Log('Die Bestätigung des Nutzungshinweises konnte nicht gespeichert werden.');
      SetIniString('Nutzungshinweis', 'Zeitpunkt', GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':'), UsageAcknowledgementPath);
      SetIniString('Nutzungshinweis', 'SetupVersion', '{#AppVersion}', UsageAcknowledgementPath);
    end;
  end;
end;

function InstallYt: Boolean;
begin
  Result := NeedYt;
end;

function InstallFFmpeg: Boolean;
begin
  Result := NeedFFmpeg;
end;

function InstallDeno: Boolean;
begin
  Result := NeedDeno;
end;

function HasWebView2: Boolean;
var
  Version: String;
  ClientPath: String;
begin
  ClientPath := 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := (RegQueryStringValue(HKLM32, ClientPath, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0')) or
    (RegQueryStringValue(HKCU, ClientPath, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0'));
end;

procedure EnsureWebView2;
var
  ExitCode: Integer;
begin
  if HasWebView2 then exit;
  WizardForm.StatusLabel.Caption := 'Microsoft Edge WebView2 wird eingerichtet …';
  ExtractTemporaryFile('MicrosoftEdgeWebview2Setup.exe');
  if not Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'), '/silent /install', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    RaiseException('Der Microsoft-WebView2-Installer konnte nicht gestartet werden.');
  if not HasWebView2 then
    RaiseException('Microsoft Edge WebView2 konnte nicht eingerichtet werden (Code ' + IntToStr(ExitCode) + ').');
end;

function HasLegacy: Boolean;
begin
  Result := DirExists('D:\YT-DLP\config');
end;

function CheckLegacyPath: Boolean;
var
  Path: String;
begin
  Path := AddBackslash(ExpandConstant('{app}'));
  Result := CompareText(Copy(Path, 1, Length('D:\YT-DLP\')), 'D:\YT-DLP\') <> 0;
end;

procedure PreparePackage(const Name, URL, Hash: String);
var
  ArchiveName, Destination: String;
begin
  WizardForm.StatusLabel.Caption := 'Lade und prüfe ' + Name + ' …';
  ArchiveName := Name + '.zip';
  Destination := ExpandConstant('{tmp}\') + Name;
  DownloadTemporaryFile(URL, ArchiveName, Hash, nil);
  if not ForceDirectories(Destination) then
    RaiseException('Temporärer Ordner konnte nicht erstellt werden.');
  ExtractArchive(ExpandConstant('{tmp}\') + ArchiveName, Destination, '', True, nil);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  PackageName, TempPath: String;
  FreeBytes, TotalBytes, RequiredBytes: Int64;
begin
  Result := '';
  if (WizardSilent and not HasUsageAcknowledgement) or
    (not WizardSilent and not WizardForm.LicenseAcceptedRadio.Checked) then begin
    Result := 'Bitte das Setup interaktiv starten und den Hinweis zur rechtmäßigen Nutzung bestätigen. Unbeaufsichtigte Updates setzen eine bereits bestätigte Fassung voraus.';
    exit;
  end;
  if not CheckLegacyPath then begin
    Result := 'Bitte einen separaten Programmordner außerhalb von D:\YT-DLP wählen.';
    exit;
  end;
  NeedYt := not (FileExists(ExpandConstant('{app}\yt-dlp.exe')) and DirExists(ExpandConstant('{app}\_internal')));
  NeedFFmpeg := not (FileExists(ExpandConstant('{app}\bin\ffmpeg.exe')) and
    FileExists(ExpandConstant('{app}\bin\ffprobe.exe')) and FileExists(ExpandConstant('{app}\bin\ffplay.exe')));
  NeedDeno := not FileExists(ExpandConstant('{app}\bin\deno.exe'));
  RequiredBytes := 20 * 1024 * 1024;
  if NeedYt then RequiredBytes := RequiredBytes + 75 * 1024 * 1024;
  if NeedFFmpeg then RequiredBytes := RequiredBytes + 450 * 1024 * 1024;
  if NeedDeno then RequiredBytes := RequiredBytes + 150 * 1024 * 1024;
  TempPath := ExpandConstant('{tmp}');
  if GetSpaceOnDisk64(TempPath, FreeBytes, TotalBytes) and (FreeBytes < RequiredBytes) then begin
    Result := 'Zu wenig freier Speicher für die Installationsdateien. Bitte mindestens ' +
      IntToStr(RequiredBytes div (1024 * 1024)) + ' MB auf diesem Laufwerk freimachen: ' + TempPath;
    exit;
  end;
  try
    PackageName := 'WebView2';
    EnsureWebView2;
    PackageName := 'yt';
    if NeedYt then PreparePackage(PackageName,
      'https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp_win.zip',
      'fd51b212cf8380c7a52ee08c0d6be7f3c59b2f2c832eaf7b45acfae6eab57419');
    PackageName := 'ff';
    if NeedFFmpeg then PreparePackage(PackageName,
      'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip',
      '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba');
    PackageName := 'deno';
    if NeedDeno then PreparePackage(PackageName,
      'https://github.com/denoland/deno/releases/download/v2.9.8/deno-x86_64-pc-windows-msvc.zip',
      'cba84b26e0df5ae7f74fc66b86a95b866872a86292ebd84fa1e959927edd93bf');
  except
    Result := 'Werkzeugpaket ' + PackageName + ': ' + GetExceptionMessage;
  end;
end;
