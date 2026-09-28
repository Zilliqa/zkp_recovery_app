# Running the Migration App on Windows

This guide will help you run the Migration App on a Windows computer, step by step. No technical experience is needed — just follow each step in order.

**Before you start:**
- This takes about **20–30 minutes**, most of which is just waiting for things to install.
- You'll be copying and pasting commands into two different black text windows. That's normal — we'll tell you exactly what to type at each step.
- If something on your screen doesn't match what's described here exactly, that's usually okay — computers vary a little. Keep going, and check the **Troubleshooting** section near the end if you get stuck.

---

## What you'll need

- A Windows computer (Windows 10 from 2020 or later, or Windows 11)
- About 20–30 minutes
- An internet connection

---

## Part 1: Set up Windows to run the app

Windows can't run this app directly — it needs a small "Linux helper" installed first, called **WSL**. Don't worry about what that means technically; just follow these steps.

### Step 1: Check your Windows version

1. Press the **Windows key** and **R** at the same time.
2. Type `winver` and press Enter.
3. A small window will show your Windows version. As long as it's a reasonably recent Windows 10 or 11, you're fine.

### Step 2: Open the Command Prompt as an Administrator

1. Click the **Start** menu and type `Command Prompt`.
2. You'll see "Command Prompt" appear in the search results. **Right-click** it.
3. Choose **"Run as administrator"**.
4. If Windows asks "Do you want to allow this app to make changes?", click **Yes**.

You should now see a black window with white text. This is the **Command Prompt** — we'll call it "the Windows window" for the rest of this guide.

### Step 3: Install the Linux helper (WSL)

In the Windows window, type this and press Enter:

```
wsl --install -d Ubuntu-24.04
```

This downloads and installs everything needed — it can take a few minutes. You'll see progress messages like this:

```
Enabling feature(s)
[==========================100.0%==========================]
```

**If it asks you to restart your computer, do that now**, then come back to this guide. After restarting, open the Windows window again (Step 2) and repeat this step — it will continue where it left off.

Eventually, a **new window** will open by itself and ask you to create a username and password for Linux. This is separate from your Windows password — pick anything you'll remember. (When typing the password, nothing will appear on screen as you type — that's normal, just type it and press Enter.)

Once that's done, you'll see something like:

```
yourname@DESKTOP:~$
```

This is a different window from before — we'll call it "the Linux window." Keep this in mind: **from now on, some instructions go in the Windows window, and some go in the Linux window.** We'll always tell you which one.

---

## Part 2: Get everything ready inside Linux

Make sure you're in **the Linux window** (the one that ends with `$`) for this whole part.

### Step 4: Update Linux

Copy and paste this, then press Enter:

```
sudo apt update && sudo apt upgrade -y
```

It may ask for the password you created in Step 3 — type it (again, it won't show on screen) and press Enter. This step can take a few minutes.

### Step 5: Test that graphics work

The app has a visible window like a normal program, so we need to check that Linux can show windows on your Windows desktop. Type:

```
sudo apt install gnome-text-editor -y
```

Then, once that finishes, type:

```
gnome-text-editor
```

**A little text editor window should pop up on your screen.** If it does, everything is working — close it and continue. (If it doesn't appear, see Troubleshooting below.)

---

## Part 3: Download and run the Migration App

### Step 6: Download the app

Using your normal Windows web browser, go to:

```
https://github.com/Zilliqa/zkp_recovery_app/releases/latest
```

Download the file called **`zkp-migration-app-linux-amd64.tar.gz`**. It will land in your Windows **Downloads** folder, same as any other download.

### Step 7: Move the app into Linux

Back in **the Linux window**, copy and paste these commands one at a time (press Enter after each):

```
mkdir -p ~/migration-app
cd ~/migration-app
```

Now we need to copy the file you downloaded into this folder. Type this, replacing `YOUR_WINDOWS_USERNAME` with your actual Windows username (the name you log into Windows with):

```
cp /mnt/c/Users/YOUR_WINDOWS_USERNAME/Downloads/zkp-migration-app-linux-amd64.tar.gz .
```

**Not sure what your Windows username is?** Type this and look at the list of folders — one of them is your username:

```
ls /mnt/c/Users/
```

### Step 8: Unpack the app

Type:

```
tar -xzf zkp-migration-app-linux-amd64.tar.gz
```

This unpacks the app. Nothing visible happens — that's normal.

### Step 9: Run the app!

Type:

```
./zkp_migration_app
```

**A window should open on your screen** — that's the Migration App, running. 🎉

---

## Running the app again later

You don't need to repeat all of this every time. Next time:

1. Open the **Start menu**, search for **Ubuntu**, and open it. This gives you the Linux window directly.
2. Type:
   ```
   cd ~/migration-app
   ./zkp_migration_app
   ```

That's it.

---

## Troubleshooting

### The text editor (Step 5) never appeared

Try running the same command again:

```
gnome-text-editor
```

If it still doesn't work, it usually means the graphics setup needs a moment to finish after installing WSL — try **restarting your computer** and opening the Linux window again (Start menu → search "Ubuntu").

### "sudo: command not found" or similar odd errors

This usually means a command was typed into **the wrong window**. Double check: commands starting with `sudo`, `apt`, `tar`, `cd`, `ls`, or `./` all go in **the Linux window** (the one ending in `$`). Only `wsl --install` and similar `wsl ...` commands go in **the Windows window**.

### "No such file or directory" when copying the downloaded file (Step 7)

This almost always means the Windows username in the command doesn't match yours, or the file didn't finish downloading. Run:

```
ls /mnt/c/Users/YOUR_WINDOWS_USERNAME/Downloads/
```

and check the exact filename that appears — make sure it matches what you're typing.

### The app window doesn't open (Step 9), or you see error text instead

1. First confirm the graphics test from Step 5 still works — run `gnome-text-editor` again. If that doesn't open either, restart your computer and try again.
2. If the text editor opens fine but the app still doesn't, copy the error text you see and reach out for help — the exact wording will tell us what's wrong.

### "Permission denied" when running `./zkp_migration_app`

Type this once, then try running the app again:

```
chmod +x zkp_migration_app
```

---

## Need more help?

If you've followed every step and something still isn't working, reach out with:
- Which step number you're stuck on
- The exact text/error you see on screen (a screenshot is even better)
