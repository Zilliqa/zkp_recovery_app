# Running the Migration App on Linux

![Linux desktop screenshot](linux.png)

This guide will help you run the Migration App on a Linux computer, step by step. (Tested on Ubuntu 24.04.)

**Before you start:**
- This takes about **5–10 minutes**.
- You'll be copying and pasting commands into a terminal window. That's normal — we'll tell you exactly what to type at each step.
- If you get stuck, check the **Troubleshooting** section near the end.

---

## What you'll need

- A computer running Linux (tested on Ubuntu 24.04)
- About 5–10 minutes
- An internet connection

---

## Step 1: Open a terminal

A terminal is a window where you type commands instead of clicking things. On Ubuntu, press **Ctrl + Alt + T**, or search for "Terminal" in your applications menu and open it.

You should see a window with text ending in something like `yourname@computer:~$`. We'll call this "the terminal window" for the rest of this guide.

## Step 2: Create a folder for the app

Copy and paste this, then press Enter:

```
mkdir -p ~/migration-app
cd ~/migration-app
```

This keeps everything for the app in one place, so it's easy to find later.

## Step 3: Download the app

1. Open this page in your browser: **https://github.com/Zilliqa/zkp_recovery_app/releases/latest**
   **Only download from this address** — never from anywhere else.
2. Find the file named `zkp-migration-app-linux-amd64.tar.gz`, right-click it, and choose **"Copy Link"**.
3. Back in the terminal window, type `wget ` (with a space after it), then paste the link you copied, and press Enter. It should look something like this:
   ```
   wget https://github.com/Zilliqa/zkp_recovery_app/releases/download/v0.5.1/zkp-migration-app-linux-amd64.tar.gz
   ```

This downloads the app into the folder you created in Step 2.

## Step 4: Verify the download (recommended)

This step checks that the file wasn't tampered with or corrupted while downloading.

Type:

```
sha256sum zkp-migration-app-linux-amd64.tar.gz
```

This prints a long string of letters and numbers. Compare it against the checksum value listed on the official release page. **If it doesn't match exactly, don't proceed** — delete the file and download it again.

## Step 5: Unpack the app

Type:

```
tar -xzf zkp-migration-app-linux-amd64.tar.gz
```

Nothing visible happens — that's normal. This creates the app's files inside your `~/migration-app` folder.

## Step 6: Run the app

Type:

```
./zkp_migration_app
```

**A window should open on your screen** — that's the Migration App, running.

---

## Running the app again later

You don't need to repeat all of this every time. Next time, just open a terminal and type:

```
cd ~/migration-app
./zkp_migration_app
```

---

## Troubleshooting

### "wget: command not found"

Most Linux systems already include `wget`. If yours doesn't, install it with:

```
sudo apt install wget -y
```

Then try Step 3 again.

### The checksum in Step 4 doesn't match

This usually means the download was interrupted or incomplete. Delete the file and download it again:

```
rm zkp-migration-app-linux-amd64.tar.gz
```

Then repeat Step 3.

### "Permission denied" when running `./zkp_migration_app`

Type this once, then try running the app again:

```
chmod +x zkp_migration_app
```

### The app window doesn't open, or you see error text instead

Copy the error text you see and reach out for help — the exact wording will tell us what's wrong.

---

## Need more help?

If you've followed every step and something still isn't working, reach out with:
- Which step number you're stuck on
- The exact text/error you see on screen (a screenshot is even better)

---

## Building from source (for developers)

This section is only for developers who want to build the app from its source code instead of using the pre-built download above. Most users should skip this section entirely.

1. Download the source code:
   ```
   git clone https://github.com/Zilliqa/zkp_recovery_app.git
   ```
2. Install and build [Mopro](../README.md).
3. Install [Flutter](https://docs.flutter.dev/platform-integration/linux/setup).
4. Build the Linux application:
   ```
   cd flutter
   flutter build linux
   ```
5. Run it:
   ```
   build/linux/x64/debug/bundle/zkp_migration_app
   ```
