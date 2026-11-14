; XOrder POS — Windows installer, one per app (pos-split-apps stage 5).
;
; Built by .github/workflows/windows-installer.yml, once per app, which passes
; the app, the version and where the staged files are:
;
;   iscc /DFlavor=Offline /DAppVersion=1.2.0
;        /DPgDir=..\build\installer\pgsql /DToolsDir=..\build\installer\tools
;        installer\xorder-pos.iss
;
; /DFlavor is Offline (the default) or Cloud and nothing else: it picks the
; product name, the exe, the build folder, the icon, the setup file's name and
; the AppId. Anything else stops the compile rather than producing an
; installer that is half one app and half the other.
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
; One app per machine (D3). Both apps share %ProgramData%\XOrder POS — pgdata,
; the credentials file, the logs — and the XOrderPOS-PostgreSQL service, on
; purpose: a machine that changes app, or leaves today's single "XOrder POS",
; uninstalls the old one (which keeps the data) and the new one finds the same
; database. A data folder per app would have stranded that database on every
; switch. The price is that the two must never be installed side by side, so
; InitializeSetup refuses while the other one is (D5).
;
; Running the same installer again upgrades in place. The database service is
; stopped first — its files are in use otherwise — and provision.ps1 then runs
; any new migrations and starts it again. Uninstalling removes the app and the
; service and leaves the data: a trading history is not an uninstaller's to
; delete.

#ifndef Flavor
  #define Flavor "Offline"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef PgDir
  #define PgDir "..\build\installer\pgsql"
#endif
#ifndef ToolsDir
  #define ToolsDir "..\build\installer\tools"
#endif

; The AppIds (D6). Never change either: it is how Windows knows a later
; installer of the same app is an upgrade rather than a second copy. Neither
; reuses the single app's id, so today's "XOrder POS" entry is never taken
; for one of these. The workflow repeats both for its refusal check; never
; change one there alone.
#define OfflineGuid "541470B8-9655-4C8B-B613-BDE215C517D6"
#define CloudGuid "CFE3951B-E0DC-4C64-908C-5BCAB02681F5"
; Today's single "XOrder POS" (before pos-split-apps). Never installed by this
; script again; only looked for, so the refusal can name it.
#define LegacyGuid "6B0C8F3E-2B6A-4F43-9C8D-58E4A1B7D9C2"
#define LegacyName "XOrder POS"

; Each branch sets every name outright rather than deriving it from Flavor's
; spelling, so the result cannot depend on how ISPP compares case.
#if Flavor == "Offline"
  #define AppName "XOrder POS - Offline"
  #define AppSlug "offline"
  #define SetupSlug "Offline"
  #define AppGuid OfflineGuid
  #define OtherGuid CloudGuid
  #define OtherName "XOrder POS - Cloud"
#elif Flavor == "Cloud"
  #define AppName "XOrder POS - Cloud"
  #define AppSlug "cloud"
  #define SetupSlug "Cloud"
  #define AppGuid CloudGuid
  #define OtherGuid OfflineGuid
  #define OtherName "XOrder POS - Offline"
#else
  #error Flavor must be Offline or Cloud
#endif

#define AppExe "xorder_pos_" + AppSlug + ".exe"
#define AppProject "..\apps\xorder_pos_" + AppSlug
#ifndef AppDir
  #define AppDir AppProject + "\build\windows\x64\runner\Release"
#endif
; Inno reads "{{" as a literal brace; the closing one needs no escape.
#define AppIdSetup "{{" + AppGuid + "}"
#define DbService "XOrderPOS-PostgreSQL"

; The Cloud app keeps its data in an encrypted SQLite file it makes itself
; (pos-cloud-single-till-sqlite): it ships no PostgreSQL, no pos_migrate, no
; provisioning script, and has no "till only" type — every cloud till stands
; alone. Everything below that installs or drives a database is Offline's.
#if Flavor == "Offline"
  #define AppComponent "Components: app; "
#else
  #define AppComponent ""
#endif

[Setup]
AppId={#AppIdSetup}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=XOrder
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=XOrder-POS-{#SetupSlug}-Setup-{#AppVersion}
SetupIconFile={#AppProject}\windows\runner\resources\app_icon.ico
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
english.CompApp={#AppName}
arabic.CompApp={#AppName}
english.CompDatabase=Database (PostgreSQL)
arabic.CompDatabase=قاعدة البيانات (PostgreSQL)
english.TaskLan=Let other tills on this network use this database
arabic.TaskLan=السماح لأجهزة الكاشير الأخرى على هذه الشبكة باستخدام قاعدة البيانات
english.SettingUpDatabase=Setting up the database…
arabic.SettingUpDatabase=جارٍ إعداد قاعدة البيانات…
english.DatabaseFailed=The database could not be set up (code %1). The log is at %2.
arabic.DatabaseFailed=تعذّر إعداد قاعدة البيانات (الرمز %1). السجل في %2.
english.DatabaseReady=The database is ready. Its accounts and passwords are in %1 — only administrators can open that file. The setup wizard will ask for them when {#AppName} first starts.
arabic.DatabaseReady=قاعدة البيانات جاهزة. الحسابات وكلمات المرور في %1 — ولا يفتح هذا الملف إلا المسؤولون. سيطلبها معالج الإعداد عند أول تشغيل لـ {#AppName}.
english.LanSecured=Other tills will reach this database over an encrypted connection. When you set each one up, compare the certificate fingerprint it shows with the one under Management › Devices on this machine.
arabic.LanSecured=ستتصل أجهزة الكاشير الأخرى بقاعدة البيانات هذه عبر اتصال مشفّر. عند إعداد كل جهاز، قارن بصمة الشهادة التي يعرضها بالبصمة الظاهرة في الإدارة › الأجهزة على هذا الجهاز.
english.LanTlsFailed=The database is ready on this machine, but other tills cannot use it yet: the network certificate could not be made, and the network is never opened without one. The log is at %1.
arabic.LanTlsFailed=قاعدة البيانات جاهزة على هذا الجهاز، لكن لا تستطيع أجهزة الكاشير الأخرى استخدامها بعد: تعذّر إنشاء شهادة الشبكة، ولا تُفتح الشبكة أبداً بدونها. السجل في %1.
english.CertificateRenewed=The network certificate was close to expiring and has been replaced. Pair every till on the network with this machine again.
arabic.CertificateRenewed=اقتربت شهادة الشبكة من انتهاء صلاحيتها فاستُبدلت. أعد إقران كل جهاز كاشير على الشبكة بهذا الجهاز.
english.LanCarriedOver=Tills set up before this version connect without encryption, and this database still lets them, alongside encrypted ones. On each till, open Management › Devices and turn encryption back on; then run setup with encryption required. The log has the command.
arabic.LanCarriedOver=أجهزة الكاشير التي أُعدّت قبل هذا الإصدار تتصل بلا تشفير، وما زالت قاعدة البيانات هذه تسمح لها بذلك إلى جانب الاتصالات المشفّرة. على كل جهاز، افتح الإدارة › الأجهزة وأعد تشغيل التشفير؛ ثم شغّل الإعداد مع اشتراط التشفير. الأمر مكتوب في السجل.

; %1 is the installed app's name, which stays in Latin script in Arabic (D8).
english.OtherAppInstalled=%1 is installed on this computer, and only one XOrder POS app can be installed on a computer.%n%nUninstall %1 first (Settings › Apps), then run this installer again. Uninstalling it keeps its database.%n%nNothing has been changed.
arabic.OtherAppInstalled=التطبيق %1 مثبّت على هذا الجهاز، ولا يُثبَّت على الجهاز الواحد إلا تطبيق واحد من XOrder POS.%n%nأزل تثبيت %1 أولاً (الإعدادات › التطبيقات)، ثم شغّل هذا المثبّت مرة أخرى. إزالة التثبيت تُبقي قاعدة بياناته.%n%nلم يُغيَّر شيء على هذا الجهاز.

#if Flavor == "Offline"
[Types]
Name: "server"; Description: "{cm:TypeServer}"
Name: "till"; Description: "{cm:TypeTill}"

[Components]
Name: "app"; Description: "{cm:CompApp}"; Types: server till; Flags: fixed
Name: "database"; Description: "{cm:CompDatabase}"; Types: server
#endif

[Tasks]
#if Flavor == "Offline"
Name: "lan"; Description: "{cm:TaskLan}"; Components: database; Flags: unchecked
#endif
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#AppDir}\*"; DestDir: "{app}"; {#AppComponent}Flags: ignoreversion recursesubdirs createallsubdirs
#if Flavor == "Offline"
; Beside the app, where PgTools looks first — so the Backup screen finds the
; pg_dump that matches this server without anybody configuring anything.
Source: "{#PgDir}\*"; DestDir: "{app}\pgsql"; Components: database; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ToolsDir}\pos_migrate.exe"; DestDir: "{app}\tools"; Components: database; Flags: ignoreversion
Source: "provision.ps1"; DestDir: "{app}\tools"; Components: database; Flags: ignoreversion
#endif
Source: "{#ToolsDir}\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; The Visual C++ runtime both the app and PostgreSQL need. Quiet, and a no-op
; where a current one is already installed.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Visual C++ runtime…"; Flags: waituntilterminated
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

#if Flavor == "Offline"
[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\tools\provision.ps1"" -AppDir ""{app}"" -Uninstall"; Components: database; Flags: runhidden waituntilterminated; RunOnceId: "RemoveDbService"
#endif

[Code]
// The uninstall key Inno writes for an AppId, wherever one can be: an admin
// install writes HKLM, a per-user one HKCU, and on 64-bit Windows the two
// registry views are separate. Today's app was always a 64-bit admin install
// (HKLM, 64-bit view), but a test machine may hold anything, and looking in
// a view that is empty costs nothing.
function UninstallKeyPresent(const Guid: String): Boolean;
var
  Key: String;
begin
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{' + Guid + '}_is1';
  Result := RegKeyExists(HKLM, Key) or RegKeyExists(HKCU, Key);
  if (not Result) and IsWin64 then
    Result := RegKeyExists(HKLM32, Key) or RegKeyExists(HKLM64, Key) or
      RegKeyExists(HKCU32, Key) or RegKeyExists(HKCU64, Key);
end;

// One app per machine (D3, D5). The other app, or today's single "XOrder
// POS", shares this one's data folder and database service, so installing
// beside it would leave two apps driving one service, and either uninstaller
// removing that service from under the other. Refused here, before any page
// or file, so nothing on the machine changes. Uninstalling the other app
// from here was rejected: it is the restaurant's till to remove, and an
// installer that silently takes one away is worse than one that asks. This
// app's own key is never looked at, so re-installing or upgrading it carries
// on as before. Returning False ends setup with exit code 1; the workflow's
// refusal check relies on that.
function InitializeSetup(): Boolean;
var
  Installed: String;
begin
  Installed := '';
  if UninstallKeyPresent('{#OtherGuid}') then
    Installed := '{#OtherName}'
  else if UninstallKeyPresent('{#LegacyGuid}') then
    Installed := '{#LegacyName}';

  Result := Installed = '';
  if not Result then
    SuppressibleMsgBox(FmtMessage(CustomMessage('OtherAppInstalled'), [Installed]),
      mbCriticalError, MB_OK, IDOK);
end;

#if Flavor == "Offline"
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
    SuppressibleMsgBox(FmtMessage(CustomMessage('DatabaseFailed'), [IntToStr(ResultCode),
      LogFile]), mbError, MB_OK, IDOK);
  end;
end;
#endif

