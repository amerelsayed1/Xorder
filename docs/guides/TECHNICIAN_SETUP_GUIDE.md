# XOrder POS — Technician setup guide

[النسخة العربية](TECHNICIAN_SETUP_GUIDE.ar.md)

For the person installing XOrder POS at a restaurant, café, food truck or kitchen.
It covers a new install on Windows 10/11 (64-bit), for both versions:

- **Cloud**: the till sells locally and sends its sales to xorder.io. Most settings come from the restaurant's dashboard.
- **Offline**: everything stays in the building. The till only contacts xorder.io to activate and renew its licence.

The licence decides which version a till can run. You don't pick it yourself.

> Verified against source: `xorder-pos` at `c67c754` (2026-10-27), `xorder-cloud` web dashboard, on 2026-11-04. See "Status of this guide" at the end.

---

## 1. Before you go on site

Collect these from the office or the restaurant owner:

| You need | From | Notes |
|---|---|---|
| **Licence key** (looks like `XXXX-XXXX-XXXX-XXXX`) | XOrder Super Admin / supplier | Activation needs **internet once**, on the main device. Bring a mobile hotspot if the site has none. |
| **How many tills** the licence covers | Same | One till = database on that machine. Several tills = one machine keeps the database, the others connect to it over the network. |
| **Cloud only: a setup code for each till** | Restaurant dashboard on xorder.io → **Settings → Devices**. Add a terminal and a code appears. | A code is valid for about **24 hours** and claims one till. Get a new one if it expires. |
| **Offline only: the first administrator** | Restaurant owner | Their full name, a username, and a **4-digit PIN** (exactly 4, the keypads submit on the 4th digit). |
| **Offline only: money settings** | Restaurant owner | Currency, service charge and VAT, to confirm on the Money step. |
| The XOrder POS installer (`.exe`) | XOrder | Use the newest release. |

On site, check:

- The machine is **Windows 10 or 11, 64-bit**, and you have a Windows **Administrator** account.
- For several tills: all tills are on the **same restaurant network**, the network is set to **Private** in Windows, and the machine that keeps the database has a **fixed address**. Reserve its IP on the router, for example `192.168.1.20`.
- The receipt printer is plugged in and switched on before you start the wizard. The wizard looks for printers.

---

## 2. Pick the layout

| Site | Machine 1 | Other machines |
|---|---|---|
| **One till** (café counter, food truck) | Installer type **"This machine keeps the database"** | none |
| **Several tills** (restaurant, busy café) | **"This machine keeps the database"** and tick **"Let other tills on this network use this database"** | Installer type **"Till only"** on each |

Always set up the machine that keeps the database (the **main device**) **first**, all the way to the till's start screen. The other tills get the licence, staff and menu from it.

---

## 3. Install on the main device

1. Sign in to Windows as an Administrator and run the installer.
2. Choose the installer language (Arabic or English).
3. Choose the type **This machine keeps the database** (هذا الجهاز يحفظ قاعدة البيانات).
4. For several tills only: tick **Let other tills on this network use this database**. Leave it off for one till.
5. Finish. The installer:
   - installs the app and PostgreSQL 16 under `C:\Program Files\XOrder POS\`;
   - creates the database service **`XOrderPOS-PostgreSQL`** (starts automatically with Windows);
   - creates the database and its three accounts, with strong random passwords;
   - saves those passwords in `C:\ProgramData\XOrder POS\install-credentials.json`;
   - writes what it did to `C:\ProgramData\XOrder POS\logs\provision.log`.
6. If you ticked the network option, the installer shows a message about the **certificate fingerprint**. Keep it in mind; you will compare it on each other till (section 6).

### The database accounts (don't change these names)

| Account | What it is for | Where you will need its password |
|---|---|---|
| `pos_admin` | Owns the database. Used by setup and by the Management screen. | Offline wizard; every time someone opens Management |
| `pos_till` | What the till uses for daily selling. Can't change prices or staff. | Offline wizard; each "Till only" machine |
| `pos_backup` | Nightly backups. Read-only. | Management → Backup → Backup account |
| `postgres` | Server superuser. | Never needed for normal work. Don't use it for the till. |

**How to read the passwords:** only Administrators can open `install-credentials.json`. Open Notepad with **Run as administrator**, then open the file.

- Never photograph it, send it in WhatsApp, or leave a copy on the desktop.
- Give the owner the `pos_admin` password in a sealed way they can keep (it opens Management). The cashiers never need any of these passwords.

---

## 4. Setup wizard: Cloud version

The app opens after install. If it shows **"This terminal has not been set up."**, press **Ctrl+Shift+S** to open the setup wizard. The wizard starts in Arabic; the language switch is in the bar at the top of every screen.

On a cloud main device the wizard asks almost nothing. It reads the database passwords from the install and the rest from xorder.io.

| Step | What to do |
|---|---|
| **Licence** (الترخيص) | Type the licence key and press **Activate online** (تفعيل عبر الإنترنت). A licence already on this machine is restored automatically. |
| **Setup type** (نوع التشغيل) | Only shown if the licence covers both versions. Choose **Cloud**. |
| **Setup code** (كود الإعداد) | Type the setup code from the dashboard (Settings → Devices). The branch, till name and settings come with it. |
| **Connecting** (جارٍ التجهيز) | Nothing to type. It prepares the database, downloads the menu and finds the printer. Wait for it to finish. |
| **Hardware** (الأجهزة) | Only shown if it found **no printer or more than one**. Pick the receipt printer. |
| **Ready** (جاهز) | Check the summary and press **Open the till** (افتح الكاشير). |

No setup code? **Sign in instead** (سجّل الدخول بدلاً من ذلك) lets a manager sign in with their xorder.io username and password. The wizard then also asks for **Branch** and **Terminal** (the till's name). Prefer the setup code: it avoids typing a staff password on a till in a public room.

---

## 5. Setup wizard: Offline version

Press **Ctrl+Shift+S** if the wizard doesn't open by itself. Have `install-credentials.json` open (section 3); you will copy two passwords from it.

| Step | What to do |
|---|---|
| **Licence** (الترخيص) | Type the key and press **Activate online**. This needs internet once; after that the till works without it. |
| **Language** (اللغة) | Language of this till. |
| **Setup type** (نوع التشغيل) | Only shown if the licence covers both. Choose **Offline**. |
| **Connection** (الاتصال) | Port as in `install-credentials.json` (normally `5432`), database user **`pos_till`**, its password from the file. Keep the suggested database name (made from the restaurant's name, e.g. `good_cafe_db`). The host field only appears on a licence for more than one till; on the main device it is `localhost`. Press **Test connection** (اختبار الاتصال). On a first install it may say the database **doesn't exist yet**: that is normal, the next step creates it. A refused password or an unreachable address is a real problem. |
| **First administrator** (أول مدير), page 1 | The **`pos_admin`** password from the file. |
| **First administrator**, page 2 | Owner's name, username and 4-digit PIN (twice). Press the button to build the database. It lists what it created. |
| **Branch** (الفرع) | Pick the branch (a new install has one, **Main**). |
| **Terminal** (الجهاز) | Name the till, e.g. `Counter 1`, and press **Register this terminal** (تسجيل هذا الجهاز). |
| **Hardware** (الأجهزة) | Printer, cash drawer, scanner. All optional. |
| **Money** (النقود) | Confirm currency, service charge and VAT with the owner. These stay on the till until the owner changes them in Management → Tax. |
| **Catalogue** (المنيو) | "No menu on this terminal" is normal on a new till. The menu is built in Management. |
| **Ready** (جاهز) | Check the summary and press **Open the till**. |

**Licence renewal:** an offline till must reach the internet to renew its licence inside the window the licence allows. If it misses the window, the **next** shift is blocked, never the open one. Tell the owner.

---

## 6. Install the other tills (several tills only)

Do this only after the main device reaches its start screen.

1. On the main device, note:
   - its network address (shown in the app's **Settings**);
   - the **certificate fingerprint** under **Management → Devices**.
2. On the other machine, run the installer and choose **Till only (connects to the machine that keeps the database)**.
3. Open the app. The wizard opens on **Main device** (الجهاز الرئيسي):
   - **Main device address** (عنوان الجهاز الرئيسي): for example `192.168.1.20`.
   - The **`pos_till` password** from the main device's `install-credentials.json`.
   - Press **Connect to the main device** (الاتصال بالجهاز الرئيسي).
4. The till shows the certificate fingerprint of the main device. **Compare it character by character** with the one on the main device. Only if they match, press **The fingerprints match — trust this server**. If they don't match, stop: you may be connected to the wrong machine.
5. **Sign in** with a manager's username and PIN that already exist on the main device.
6. **Branch**, **Terminal** (give it its own name, e.g. `Counter 2`), **Hardware**, **Catalogue**, **Ready**.

If it says **all terminals are registered**, the licence is full. Retire an old till on the main device, or ask for a licence with more terminals.

If it says **the main device has not shared its licence yet**, open XOrder POS on the main device until it reaches its start screen, then connect again.

---

## 7. After setup: hand-over checklist

- [ ] **Management** opens: Management → enter the owner's PIN → enter the `pos_admin` password (the back-office password). It is asked once per session and never saved.
- [ ] Offline: the owner (or you, with them) adds the menu in **Management → Products**, and tables in **Management → Dining areas & tables** if they seat customers.
- [ ] **Backups:** Management → Backup → **Backup account**: enter the `pos_backup` password on each till that closes the day. Then use **Copy to…** to put a backup on a USB drive kept away from the till. Only the newest 14 copies stay on the machine.
- [ ] A test sale prints a receipt.
- [ ] Restart the machine: the app opens straight into the till, not the wizard.
- [ ] Several tills: every till can open a shift and sell.
- [ ] The owner has the `pos_admin` password kept safely, and knows the licence renewal rule (offline).

---

## 8. Problems you may see

| Message or symptom | What it means | Fix |
|---|---|---|
| Licence: address refused the key / platform unreachable | No internet, or wrong licence server | Check the internet (a phone hotspot is enough), and that the key was typed exactly. |
| Setup type shows Cloud greyed out (NOT LICENSED) | The licence covers Offline only | Correct; continue with Offline, or ask for a cloud licence. |
| Test connection: password not accepted | Wrong `pos_till` password | Copy it again from `install-credentials.json`. Watch for spaces. |
| Test connection: database doesn't exist yet | Normal on a first offline install | Continue; **First administrator** creates it. |
| `permission denied for schema public` | Pointing at a database someone else created by hand | Use the database the installer built. |
| Other till can't reach the main device | Network option not ticked, network set to Public, or the address changed | Re-run the installer on the main device with the network option ticked; set the network to Private; reserve the address on the router. |
| Setup code refused | Expired (over ~24 h) or already used | Make a new code in the dashboard (Settings → Devices → New code). |
| The open shift is on the "Pick a table" screen with no tables | No tables yet | Use **Sell without a table**, or add tables in Management → Dining areas & tables. |

Logs: `C:\ProgramData\XOrder POS\logs\provision.log`. Passwords never appear in it, so you can send it to support.

## 9. Upgrade and uninstall

- **Upgrade:** run the newer installer on each machine, main device first. Data and passwords are kept and the database is updated automatically.
- **Uninstall** removes the app and the database service, but **keeps the data** in `C:\ProgramData\XOrder POS\`. Never delete that folder: it is the restaurant's trading history.

## 10. macOS (not a field install)

There is no macOS installer. On a Mac, PostgreSQL and the accounts are set up by hand, and the wizard asks for the database passwords itself. Use a Mac only for demos or development; the manual steps are in `apps/xorder-pos/docs/pos/10-offline-install-runbook.md`.

---

## Status of this guide

- Steps, labels and paths were read from the current source (wizard step lists in `lib/features/setup/domain/setup_state.dart`, labels in `lib/core/l10n/app_strings.dart`, installer `installer/xorder-pos.iss`, `installer/provision.ps1` as described in `docs/pos/18-windows-installer.md`). **The guide itself has not been walked through on a real Windows machine.**
- **UNVERIFIED:** `docs/pos/18-windows-installer.md` says the installer had never been run on real Windows and that builds are unsigned (Windows SmartScreen will warn: "More info → Run anyway"). Check both before the first field install.
- **UNVERIFIED:** the exact dashboard menu path to the Devices page (route `dashboard.pos.terminals`, under the settings menu, needs the POS feature and the `pos.provision` permission).
- The wizard has **no "Activate from file" button** today (only online activation; a licence already saved on the machine is restored). The app's error text for a bad file still mentions "Activate from file": stale wording, worth fixing.
- **UNVERIFIED:** whether the offline Connection step pre-fills the port and user from the install. The source reads `install-credentials.json` automatically only on the cloud path, so this guide tells the technician to copy them.
