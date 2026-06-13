; Instalador do Downside para Windows (Inno Setup).
; Parâmetros passados pela linha de comando do CI:
;   /DMyAppVersion=<versão>   /DMySource=<pasta build Release>
#define MyAppName "Downside"
#define MyAppExeName "downside.exe"
#define MyAppPublisher "v1r8"

[Setup]
AppId={{8F3C2B71-9D4E-4A6F-B2A1-DOWNSIDEWIN01}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Downside
DefaultGroupName=Downside
DisableProgramGroupPage=yes
; Instalação por-usuário (sem UAC) — auto-update silencioso depois.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=DownsideSetup-{#MyAppVersion}
SetupIconFile=..\assets\tray.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
Source: "{#MySource}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion createallsubdirs

[Icons]
Name: "{group}\Downside"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\Downside"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir o Downside"; Flags: nowait postinstall skipifsilent
