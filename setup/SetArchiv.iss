[Setup]
AppId=SetArchiv
AppName=Plattenkoffer
AppPublisher=Mindgamer
SetupIconFile=SetArchiv.ico
UninstallDisplayIcon={app}\SetArchiv.ico
AppVersion=0.1.13
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
OutputBaseFilename=Plattenkoffer-Setup-0.1.13
WizardStyle=modern
ArchiveExtraction=full

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop-Symbol erstellen"
Name: "migrate"; Description: "Einstellungen und Downloadarchiv aus D:\YT-DLP übernehmen"; Check: HasLegacy

[Files]
Source: "Lizenzen\*"; DestDir: "{app}\Lizenzen"; Flags: ignoreversion
Source: "plattenkoffer-banner.png"; DestDir: "{app}"; Flags: ignoreversion
Source: "SetArchiv.ico"; DestDir: "{app}"; Flags: ignoreversion

Source: "DJ-Sets-*.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{tmp}\yt\yt-dlp.exe"; DestDir: "{app}"; Flags: external ignoreversion; ExternalSize: 10591079
Source: "{tmp}\yt\_internal\*"; DestDir: "{app}\_internal"; Flags: external recursesubdirs createallsubdirs ignoreversion; ExternalSize: 40000000
Source: "{tmp}\ff\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 105423872
Source: "{tmp}\ff\ffmpeg-9.0.2-essentials_build\bin\ffprobe.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 105221120
Source: "{tmp}\ff\ffmpeg-9.0.2-essentials_build\bin\ffplay.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 106903552
Source: "{tmp}\deno\deno.exe"; DestDir: "{app}\bin"; Flags: external ignoreversion; ExternalSize: 98081568
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
  PackageName: String;
begin
  Result := '';
  if not CheckLegacyPath then begin
    Result := 'Bitte einen separaten Programmordner außerhalb von D:\YT-DLP wählen.';
    exit;
  end;
  try
    PackageName := 'yt';
    PreparePackage(PackageName,
      'https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp_win.zip',
      'fd51b212cf8380c7a52ee08c0d6be7f3c59b2f2c832eaf7b45acfae6eab57419');
    PackageName := 'ff';
    PreparePackage(PackageName,
      'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip',
      '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba');
    PackageName := 'deno';
    PreparePackage(PackageName,
      'https://github.com/denoland/deno/releases/download/v2.9.8/deno-x86_64-pc-windows-msvc.zip',
      'cba84b26e0df5ae7f74fc66b86a95b866872a86292ebd84fa1e959927edd93bf');
  except
    Result := 'Werkzeugpaket ' + PackageName + ': ' + GetExceptionMessage;
  end;
end;








