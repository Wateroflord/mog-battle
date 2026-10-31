; Установщик Mog Battle для Windows (Inno Setup 6). Ставится без прав администратора в профиль пользователя.
#define BuildNo GetEnv("BUILD_NO")
#if BuildNo == ""
  #define BuildNo "0"
#endif

[Setup]
AppId={{93FB0EED-F0D2-42C9-B17B-AD65A6880E2D}
AppName=Mog Battle
AppVersion=1.0.{#BuildNo}
AppPublisher=Winter Hub
DefaultDirName={localappdata}\Programs\Mog Battle
DefaultGroupName=Mog Battle
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Mog-Battle-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mog_battle.exe
CloseApplications=force
RestartApplications=no
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Mog Battle"; Filename: "{app}\mog_battle.exe"
Name: "{group}\{cm:UninstallProgram,Mog Battle}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Mog Battle"; Filename: "{app}\mog_battle.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mog_battle.exe"; Description: "{cm:LaunchProgram,Mog Battle}"; Flags: nowait postinstall skipifsilent
; После тихого автообновления — снова запустить приложение.
Filename: "{app}\mog_battle.exe"; Flags: nowait; Check: WizardSilent
