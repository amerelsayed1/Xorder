; XOrder POS — Windows installer.
;
; Built by .github/workflows/windows-installer.yml, which passes the version
; and where the staged files are:
;
;   iscc /DAppVersion=1.2.0 /DAppDir=build\windows\x64\runner\Release
;        /DPgDir=build\installer\pgsql /DToolsDir=build\installer\tools
;        installer\xorder-pos.iss
;
; /DSIGN additionally signs the installer and uninstaller with the `signtool`
; command the build defines. Without it the installer is unsigned, and
; SmartScreen will warn whoever runs it.
;
; Two ways to install, because a restaurant has one database and possibly many
; tills: "This machine keeps the database" installs PostgreSQL beside the app
; and sets it up (installer\provision.ps1); "Till only" installs the app and
; leaves install-role.json beside the credentials file, so the app opens as a
; child of the machine that keeps the database — finding it, signing in as a
; manager who exists there — rather than as a main device with no database.
;
; Running the same installer again upgrades in place. The database service is
; stopped first — its files are in use otherwise — and provision.ps1 then runs
; any new migrations and starts it again. Uninstalling removes the app and the
; service and leaves the data: a trading history is not an uninstaller's to
; delete.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppDir
  #define AppDir "..\apps\xorder_pos_offline\build\windows\x64\runner\Release"
#endif
#ifndef PgDir
  #define PgDir "..\build\installer\pgsql"
#endif
#ifndef ToolsDir
  #define ToolsDir "..\build\installer\tools"
#endif

#define AppName "XOrder POS"
#define AppExe "xorder_pos_offline.exe"
#define DbService "XOrderPOS-PostgreSQL"

[Setup]
; Never change: it is how Windows knows a later installer is an upgrade.
AppId={{6B0C8F3E-2B6A-4F43-9C8D-58E4A1B7D9C2}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=XOrder
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=XOrder-POS-Setup-{#AppVersion}
SetupIconFile=..\apps\xorder_pos_offline\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes
MinVersion=10.0
#ifdef SIGN
SignTool=signtool
SignedUninstaller=yes
#endif

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
english.TypeServer=This machine keeps the database
arabic.TypeServer=هذا الجهاز يحفظ قاعدة البيانات
english.TypeTill=Till only (connects to the machine that keeps the database)
arabic.TypeTill=كاشير فقط (يتصل بالجهاز الذي يحفظ قاعدة البيانات)
english.CompApp=XOrder POS
arabic.CompApp=XOrder POS
english.CompDatabase=Database (PostgreSQL)
arabic.CompDatabase=قاعدة البيانات (PostgreSQL)
english.TaskLan=Let other tills on this network use this database
arabic.TaskLan=السماح لأجهزة الكاشير الأخرى على هذه الشبكة باستخدام قاعدة البيانات
english.SettingUpDatabase=Setting up the database…
arabic.SettingUpDatabase=جارٍ إعداد قاعدة البيانات…
english.DatabaseFailed=The database could not be set up (code %1). The log is at %2.
arabic.DatabaseFailed=تعذّر إعداد قاعدة البيانات (الرمز %1). السجل في %2.
english.DatabaseReady=The database is ready. Its accounts and passwords are in %1 — only administrators can open that file. The setup wizard will ask for them when XOrder POS first starts.
arabic.DatabaseReady=قاعدة البيانات جاهزة. الحسابات وكلمات المرور في %1 — ولا يفتح هذا الملف إلا المسؤولون. سيطلبها معالج الإعداد عند أول تشغيل لـ XOrder POS.
english.LanSecured=Other tills will reach this database over an encrypted connection. When you set each one up, compare the certificate fingerprint it shows with the one under Management › Devices on this machine.
arabic.LanSecured=ستتصل أجهزة الكاشير الأخرى بقاعدة البيانات هذه عبر اتصال مشفّر. عند إعداد كل جهاز، قارن بصمة الشهادة التي يعرضها بالبصمة الظاهرة في الإدارة › الأجهزة على هذا الجهاز.
english.LanTlsFailed=The database is ready on this machine, but other tills cannot use it yet: the network certificate could not be made, and the network is never opened without one. The log is at %1.
arabic.LanTlsFailed=قاعدة البيانات جاهزة على هذا الجهاز، لكن لا تستطيع أجهزة الكاشير الأخرى استخدامها بعد: تعذّر إنشاء شهادة الشبكة، ولا تُفتح الشبكة أبداً بدونها. السجل في %1.
english.CertificateRenewed=The network certificate was close to expiring and has been replaced. Pair every till on the network with this machine again.
arabic.CertificateRenewed=اقتربت شهادة الشبكة من انتهاء صلاحيتها فاستُبدلت. أعد إقران كل جهاز كاشير على الشبكة بهذا الجهاز.
english.LanCarriedOver=Tills set up before this version connect without encryption, and this database still lets them, alongside encrypted ones. On each till, open Management › Devices and turn encryption back on; then run setup with encryption required. The log has the command.
arabic.LanCarriedOver=أجهزة الكاشير التي أُعدّت قبل هذا الإصدار تتصل بلا تشفير، وما زالت قاعدة البيانات هذه تسمح لها بذلك إلى جانب الاتصالات المشفّرة. على كل جهاز، افتح الإدارة › الأجهزة وأعد تشغيل التشفير؛ ثم شغّل الإعداد مع اشتراط التشفير. الأمر مكتوب في السجل.

[Types]
Name: "server"; Description: "{cm:TypeServer}"
Name: "till"; Description: "{cm:TypeTill}"

[Components]
Name: "app"; Description: "{cm:CompApp}"; Types: server till; Flags: fixed
Name: "database"; Description: "{cm:CompDatabase}"; Types: server

[Tasks]
Name: "lan"; Description: "{cm:TaskLan}"; Components: database; Flags: unchecked
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#AppDir}\*"; DestDir: "{app}"; Components: app; Flags: ignoreversion recursesubdirs createallsubdirs
; Beside the app, where PgTools looks first — so the Backup screen finds the
; pg_dump that matches this server without anybody configuring anything.
Source: "{#PgDir}\*"; DestDir: "{app}\pgsql"; Components: database; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ToolsDir}\pos_migrate.exe"; DestDir: "{app}\tools"; Components: database; Flags: ignoreversion
Source: "provision.ps1"; DestDir: "{app}\tools"; Components: database; Flags: ignoreversion
Source: "{#ToolsDir}\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; The Visual C++ runtime both the app and PostgreSQL need. Quiet, and a no-op
; where a current one is already installed.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Visual C++ runtime…"; Flags: waituntilterminated
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\tools\provision.ps1"" -AppDir ""{app}"" -Uninstall"; Components: database; Flags: runhidden waituntilterminated; RunOnceId: "RemoveDbService"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  // An upgrade replaces files the running database service holds open.
  // Stopped here; provision.ps1 starts it again once the new files are in.
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop {#DbService}', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
  Sleep(2000);
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Params, LogFile, CredFile, RoleFile, Msg: String;
begin
  if CurStep <> ssPostInstall then
    Exit;

  // "Till only" leaves a note the app reads on its first start: this machine
  // is a client terminal of the one that keeps the database, so the wizard
  // opens on finding that machine rather than on a licence key. Written here
  // because provision.ps1 never runs on a till-only install. The value is
  // TerminalRole.child's wire form, and lib/data/config/installed_role.dart
  // reads it back. A server install deletes a stale one: a machine
  // re-installed with the database is a main device again.
  RoleFile := ExpandConstant('{commonappdata}\XOrder POS\install-role.json');
  if not WizardIsComponentSelected('database') then
  begin
    ForceDirectories(ExtractFilePath(RoleFile));
    SaveStringToFile(RoleFile, '{"role": "client_terminal"}' + #13#10, False);
    Exit;
  end;
  DeleteFile(RoleFile);

  LogFile := ExpandConstant('{commonappdata}\XOrder POS\logs\provision.log');
  CredFile := ExpandConstant('{commonappdata}\XOrder POS\install-credentials.json');
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\tools\provision.ps1') + '" -AppDir "' +
    ExpandConstant('{app}') + '"';
  if WizardIsTaskSelected('lan') then
    Params := Params + ' -Lan';

  WizardForm.StatusLabel.Caption := CustomMessage('SettingUpDatabase');
  if not Exec('powershell.exe', Params, '', SW_HIDE, ewWaitUntilTerminated,
      ResultCode) then
    ResultCode := -1;

  // provision.ps1's exit codes, listed at its top. 2 is not a failure of the
  // database — it is ready on this machine — but of the LAN, which is never
  // opened unencrypted, so it is said as an error rather than buried in a
  // success message.
  case ResultCode of
    0, 3, 4:
      begin
        Msg := FmtMessage(CustomMessage('DatabaseReady'), [CredFile]);
        if WizardIsTaskSelected('lan') then
          Msg := Msg + #13#10#13#10 + CustomMessage('LanSecured');
        if ResultCode = 3 then
          Msg := Msg + #13#10#13#10 + CustomMessage('CertificateRenewed');
        if ResultCode = 4 then
          Msg := Msg + #13#10#13#10 + CustomMessage('LanCarriedOver');
        SuppressibleMsgBox(Msg, mbInformation, MB_OK, IDOK);
      end;
    2:
      SuppressibleMsgBox(FmtMessage(CustomMessage('LanTlsFailed'), [LogFile]),
        mbError, MB_OK, IDOK);
  else
    SuppressibleMsgBox(FmtMessage(CustomMessage('DatabaseFailed'),
      [IntToStr(ResultCode), LogFile]), mbError, MB_OK, IDOK);
  end;
end;
