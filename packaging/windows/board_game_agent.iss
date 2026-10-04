; Inno Setup script for the Board Game Agent Windows release.
; The publisher passes the source and output paths through /D defines.

#ifndef AppId
  #define AppId "board_game_agent"
#endif
#ifndef AppName
  #define AppName "Board Game Agent"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppBuildNumber
  #define AppBuildNumber "0"
#endif
#ifndef AppPublisher
  #define AppPublisher "Board Game Agent"
#endif
#ifndef AppExeName
  #define AppExeName "board_game_agent.exe"
#endif
#ifndef SourceDir
  #define SourceDir "..\\..\\build\\windows\\x64\\runner\\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\\..\\release"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "board_game_agent-setup"
#endif
#ifndef AppIconFile
  #define AppIconFile "..\\..\\windows\\runner\\resources\\app_icon.ico"
#endif
#ifndef LoginProtocol
  #define LoginProtocol "org.dpdns.cznas.boardgame"
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/chenxuanjie/board-game-agent
AppSupportURL=https://github.com/chenxuanjie/board-game-agent/issues
AppUpdatesURL=https://github.com/chenxuanjie/board-game-agent/releases
DefaultDirName={localappdata}\Programs\{#AppId}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile={#AppIconFile}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
VersionInfoVersion={#AppVersion}.{#AppBuildNumber}
VersionInfoProductVersion={#AppVersion}.{#AppBuildNumber}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppExeName}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Classes\{#LoginProtocol}"; ValueType: string; ValueName: ""; ValueData: "URL:Board Game Agent Login"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#LoginProtocol}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\{#LoginProtocol}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""
