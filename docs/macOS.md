# Install the ZKP Migration App on a Mac

This guide is for Macs with an **Apple M-series chip (M1 or newer)** running **macOS 12 or later**. The app does not run on Intel Macs. To check your Mac, click the **Apple menu → About This Mac** and look for **Chip** and **macOS**.

## Step 1: Download and check the app

1. Open [Zilliqa’s official GitHub releases page](https://github.com/Zilliqa/zkp_recovery_app/releases). Under the latest release, click **Assets** if you need to expand the list. Download the macOS file whose name starts with `zkp-migration-app-macos-arm64-` and ends with `.dmg`, for example `zkp-migration-app-macos-arm64-0.6.0.dmg`. It will usually go to **Downloads**. **Do not download it from another website.**
2. On the same release page, download the file with the **same name plus `.sha256`** at the end, for example `zkp-migration-app-macos-arm64-0.6.0.dmg.sha256`. This small text file contains the official fingerprint for the app. The same fingerprint is also listed on the release page.
3. Open **Terminal**: press **Command (⌘) + Space**, type `Terminal`, then press **Return**.
4. Type `shasum -a 256` followed by **one space**. Do not press Return yet. Open **Finder → Downloads**, then **drag the downloaded `.dmg` file into Terminal**. Its location will appear after the space. Now press **Return**.
   Terminal will show a string of 64 letters and numbers followed by the file's location. That string is your download’s **fingerprint**.
5. In Finder, right-click the downloaded `.sha256` file and choose **Open With → TextEdit**. Compare the **entire fingerprint** in TextEdit with the one Terminal showed. Every character must match. Make sure both filenames refer to the same app version.

**If the fingerprints differ, or you cannot find the official fingerprint, stop. Do not install or open the app.**

## Step 2: Install the app

1. In **Finder → Downloads**, double-click the `.dmg` file you checked. A window will open showing **Zero Knowledge Migration App** and an **Applications** shortcut.
2. Drag **Zero Knowledge Migration App** onto the **Applications** shortcut. Wait for the copy to finish.
3. In the Finder sidebar, click the **eject symbol** next to **Zero Knowledge Migration App**.

Open the installed app from your **Applications** folder, not from the downloaded disk image.

## Step 3: Open the app for the first time

This version has not been notarized by Apple, so macOS may block it the first time you open it. Only continue if you downloaded it from the official release page and its fingerprint matched in Step 1.

1. Open **Finder → Applications**, then double-click **Zero Knowledge Migration App**.
2. If macOS shows a warning, click **Done** or **OK** to close it. Do not choose **Move to Trash**.
3. Open **Apple menu → System Settings → Privacy & Security**. On macOS 12, use **System Preferences → Security & Privacy → General** instead.
4. Scroll to **Security**. Find the notice saying **Zero Knowledge Migration App** was blocked and click **Open Anyway**.
5. Confirm by clicking **Open** (or **Open Anyway**). Enter your Mac password or use Touch ID if asked. The app window should open. After this, you should be able to open it normally from **Applications**.

If **Open Anyway** does not appear, or macOS says the app is damaged, stop and contact Zilliqa through its official support channels.
