# Putting Crown Conquest on your Android phone (Windows, step by step)

This guide assumes you've never exported a Godot game before. It takes about
an hour the first time, mostly waiting for downloads. You only do steps 1–5
once; after that, putting a new version on your phone takes one click.

The project is already set up for Android (landscape, app name "Crown
Conquest", a placeholder icon, the screen stays on during matches, vibration
allowed). What's missing is the software Godot needs to build an Android app.

**You'll need:** your Windows PC, your Android phone, its USB cable, and
about 10 GB of free disk space.

---

## 1. Install Java (JDK 17)

Godot uses Java's tools to sign the app.

1. Go to **https://adoptium.net/temurin/releases/**.
2. Pick **Operating System: Windows**, **Architecture: x64**, **Package Type: JDK**, **Version: 17 - LTS**.
3. Download the **.msi** file and run it.
4. On the "Custom Setup" page, click the icon next to **Set JAVA_HOME variable** and choose **"Will be installed on local hard drive"**. Then click Next / Install.
5. Check it worked: open **PowerShell** (Start menu → type `powershell`) and run:

   ```powershell
   java -version
   ```

   You should see something like `openjdk version "17.0.x"`.

   Write down where Java was installed. It's usually
   `C:\Program Files\Eclipse Adoptium\jdk-17.0.x.x-hotspot` (the exact numbers vary).

> If Godot later says it needs a different Java version, install that version
> the same way and point Godot at it (step 4).

## 2. Install the Android SDK (with Android Studio)

The Android SDK has the tools that build and install apps. The easiest way to
get it is Android Studio, even though you'll never write code in it.

1. Download Android Studio from **https://developer.android.com/studio** and install it with the default options.
2. Start Android Studio. Click through the first-run wizard with **Standard** settings and let it download everything (this takes a while).
3. On the welcome screen, click **More Actions → SDK Manager**.
4. On the **SDK Platforms** tab, tick the newest **Android** version (API 34 or higher).
5. On the **SDK Tools** tab, tick:
   - **Android SDK Build-Tools**
   - **Android SDK Command-line Tools (latest)**
   - **Android SDK Platform-Tools**
6. Click **Apply** and wait for the downloads.
7. Write down the **Android SDK Location** shown at the top of that window. It's usually
   `C:\Users\benbe\AppData\Local\Android\Sdk`.

You can close Android Studio now.

## 3. Download Godot's Android export templates

1. Open the Crown Conquest project in Godot 4.7.2 (the normal, non-console `.exe` is easiest for this part).
2. Menu **Editor → Manage Export Templates…**
3. Click **Download and Install**. Wait until it says the templates for 4.7.2 are installed.

## 4. Tell Godot where Java and the SDK are

1. Menu **Editor → Editor Settings…**
2. In the left list, open **Export → Android**.
3. Set **Java SDK Path** to your Java folder from step 1, for example
   `C:\Program Files\Eclipse Adoptium\jdk-17.0.x.x-hotspot`.
4. Set **Android SDK Path** to the folder from step 2, for example
   `C:\Users\benbe\AppData\Local\Android\Sdk`.
5. Look at **Debug Keystore** on the same page:
   - If it's already filled in, Godot made one for you: skip to step 6.
   - If it's empty, make one (next section), then come back.
6. Close Editor Settings.

### Making a debug keystore (only if Godot didn't)

A keystore is the "signature" Android uses to know an app update comes from
the same author. For testing on your own phone, a debug keystore is fine.

In PowerShell, run (all on one line):

```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "$env:USERPROFILE\debug.keystore" -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
```

Then in **Editor Settings → Export → Android**, set:

- **Debug Keystore:** `C:\Users\benbe\debug.keystore`
- **Debug Keystore User:** `androiddebugkey`
- **Debug Keystore Pass:** `android`

## 5. Get your phone ready

1. On the phone, open **Settings → About phone** and tap **Build number** 7 times. You'll see "You are now a developer". (On some phones Build number is under **Software information**.)
2. Go back to Settings and find **Developer options** (often under **System**). Turn on **USB debugging**.
3. Plug the phone into your PC with the USB cable. If the phone asks **"Allow USB debugging?"**, tick **Always allow from this computer** and tap **Allow**.
4. Check the PC can see it. In PowerShell:

   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
   ```

   You should see one line ending in `device`. If it says `unauthorized`, look at your phone for the Allow prompt. If nothing shows up, try another cable or USB port, set the phone's USB mode to **File transfer**, and for some brands (Samsung, Xiaomi) install the phone maker's USB driver.

## 6. Install the game on your phone

**The one-click way (easiest):**

1. With the phone plugged in and the project open in Godot, look at the top-right of the editor. Next to the Play buttons there's a **Remote Debug / deploy** button with an Android icon (it appears once steps 1–5 are done).
2. Click it and pick your phone. Godot builds the app, installs it and starts it. The first build takes a minute.

**Or make an .apk file:**

1. Menu **Project → Export…**, select the **Android** preset (it's already there) and click **Export Project**.
2. Save it as `export\CrownConquest.apk` inside the project folder. Untick **Export With Debug** only when you make a release build later.
3. Install it on the plugged-in phone:

   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r export\CrownConquest.apk
   ```

   (Or copy the .apk to the phone and open it there; you'll have to allow "Install unknown apps" for your file manager.)

**Or from the command line** with the console Godot you already use (run inside the project folder):

```powershell
C:\Users\benbe\Desktop\Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-debug "Android" export\CrownConquest.apk
```

The game appears on your phone as **Crown Conquest** with a gold crown icon.

---

## If something goes wrong

| Message or problem | What to do |
| --- | --- |
| "No export template found" | Do step 3 again; the templates must match Godot 4.7.2 exactly. |
| "Invalid Java SDK path" / "Java not found" | Step 4: the path must be the JDK folder that contains `bin\java.exe`. |
| "Invalid Android SDK path" / "adb not found" | Step 4: the path must be the folder that contains `platform-tools` and `build-tools`. |
| "Could not find keystore" / signing failed | Make the debug keystore (step 4) and check the user is `androiddebugkey` and both passwords are `android`. |
| The Android deploy button doesn't appear | Steps 3–5 aren't finished, or the phone isn't listed by `adb devices`. |
| "App not installed" on the phone | Uninstall the old Crown Conquest from the phone first (an older build signed with a different keystore blocks updates), then try again. |
| The game starts in portrait or the screen dims mid-match | Tell me: both should already be handled (landscape lock and keep-screen-on during matches). |
| It's slow or gets hot | Tell me the phone model and what was happening (map size, how many bots, how far into the match). |

## Later: a release build for friends or the Play Store

For a version you share widely you'll make a **release keystore** (your
permanent signature: back it up, because losing it means you can't update the
app) and export without debug. That's a separate step for later; the debug
build above is all you need to play-test on your own phone and your friends'
phones (send them the .apk).
