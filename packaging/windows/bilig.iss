; Builds Bilig-Windows-Setup.exe from the Flutter release build.
; ISCC /DAppVersion=1.2.0 /DSourceDir=..\..\build\windows\x64\runner\Release bilig.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6F1C3B0E-5D2A-4F7E-9B1C-8A4E2D7F3C51}
AppName=Bilig
AppVersion={#AppVersion}
AppPublisher=Bilig
AppPublisherURL=https://abekmurodov-cpu.github.io/bilig/
DefaultDirName={autopf}\Bilig
DefaultGroupName=Bilig
DisableProgramGroupPage=yes
; Installs for the current user, so no administrator rights are needed.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build\dist
OutputBaseFilename=Bilig-Windows-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Bilig.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Bilig"; Filename: "{app}\Bilig.exe"
Name: "{autodesktop}\Bilig"; Filename: "{app}\Bilig.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Bilig.exe"; Description: "{cm:LaunchProgram,Bilig}"; Flags: nowait postinstall skipifsilent
