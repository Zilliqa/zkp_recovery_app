# Running the ZKP Recovery App on Windows using WSL2

The ZKP Recovery App for Linux can run on Windows using **WSL2 (Windows Subsystem for Linux)** with **Ubuntu 24.04** and **WSLg**.

This guide covers:

1. Installing WSL2
2. Installing Ubuntu 24.04
3. Verifying Linux GUI support
4. Downloading/extracting the ZKP Recovery App
5. Running the pre-built Linux binary
6. Troubleshooting common WSL issues

> **Important:** WSL2 is required. WSL1 does not provide the WSLg functionality required to run the graphical Linux application.

---

## Requirements

Before proceeding, ensure your system meets the following requirements:

- **Operating System:** Windows 10 version 2004 (Build 19041) or later, or Windows 11
- **Architecture:** 64-bit processor with SLAT support
- **Virtualization:** Enabled in BIOS/UEFI
- **Graphics Driver:** An up-to-date Intel, AMD, or NVIDIA Windows graphics driver is recommended
- **WSL Version:** WSL2
- **Linux Distribution:** Ubuntu 24.04

---

# 1. Check Your Windows Version

Press:

```text
Win + R
```

Enter:

```text
winver
```

Verify that you are running a supported version of Windows.

---

# 2. Open Command Prompt as Administrator

Search for:

```text
Command Prompt
```

Right-click it and select:

```text
Run as administrator
```

The following `wsl` commands must be run from **Windows Command Prompt or PowerShell**, not from inside Ubuntu.

---

# 3. Check WSL

Run:

```cmd
wsl --status
```

You can also try:

```cmd
wsl --version
```

On a current WSL installation, this should display the installed WSL and kernel versions.

## If `wsl --version` Only Displays Help

Some Windows systems may initially have older/inbox WSL components.

For example, commands such as:

```cmd
wsl --set-default-version 2
```

or:

```cmd
wsl --version
```

may display the WSL usage/help screen instead of performing the requested operation.

This does not necessarily mean your Windows version is unsupported.

Continue with the WSL/Ubuntu installation below.

---

# 4. Install WSL2 and Ubuntu 24.04

From **Administrator Command Prompt or PowerShell**, run:

```cmd
wsl --install -d Ubuntu-24.04
```

Windows may first enable the required WSL and virtualization features.

You may see output similar to:

```text
Enabling feature(s)
[==========================100.0%==========================]

The operation completed successfully.
Changes will not be effective until the system is rebooted.
```

If Windows says that changes will not take effect until the system is rebooted:

> **Restart Windows before continuing.**

Do not try to run `sudo`, `apt`, or other Linux commands from Windows Command Prompt.

---

# 5. Complete the Ubuntu Installation

After restarting Windows, open Command Prompt and run:

```cmd
wsl --install -d Ubuntu-24.04
```

if the Ubuntu installation did not automatically continue.

Then start Ubuntu:

```cmd
wsl -d Ubuntu-24.04
```

On first launch, Ubuntu may ask you to create a Linux:

- Username
- Password

After setup, your terminal prompt should look similar to:

```text
username@DESKTOP:~$
```

For example:

```text
chetan@DESKTOP:~$
```

You are now inside Ubuntu.

---

# 6. Understand Windows CMD vs Ubuntu

This is a **Windows Command Prompt**:

```text
C:\Users\USERNAME>
```

Do not run Linux commands such as:

```bash
sudo apt update
```

there.

This is an **Ubuntu/WSL shell**:

```text
username@DESKTOP:~$
```

Linux commands such as `sudo`, `apt`, `tar`, and `chmod` must be run here.

## Do Not Type `$`

Some Linux documentation shows commands like:

```text
$ sudo apt update
```

The `$` represents the shell prompt.

Do **not** type it.

Incorrect:

```text
$ sudo apt update
```

Correct:

```bash
sudo apt update
```

---

# 7. Verify WSL2

From **Windows Command Prompt or PowerShell**, run:

```cmd
wsl -l -v
```

Expected output should look similar to:

```text
NAME            STATE           VERSION
Ubuntu-24.04    Running         2
```

Make sure the `VERSION` column shows:

```text
2
```

If supported by your WSL installation, you can also make WSL2 the default for future Linux distributions:

```cmd
wsl --set-default-version 2
```

---

# 8. Update Ubuntu

Inside the **Ubuntu terminal**, run:

```bash
sudo apt update
sudo apt upgrade -y
```

Enter your Linux password when prompted.

---

# 9. Verify WSLg GUI Support

The ZKP Recovery App is a graphical Linux application, so WSLg must be working.

Install GNOME Text Editor as a simple GUI test:

```bash
sudo apt install gnome-text-editor -y
```

Launch it:

```bash
gnome-text-editor
```

A graphical text editor window should appear directly on your Windows desktop.

If it opens successfully, WSLg is working.

> Modern WSL2 installations with WSLg do not require a separate X server or manual `DISPLAY` configuration.

Close GNOME Text Editor before continuing.

---

# 10. Download the ZKP Recovery App

Download the Linux release:

```text
zkp-recovery-app-linux-beta.tar.gz
```

using your Windows browser.

If the file is saved in your Windows Downloads folder, it will normally be accessible from Ubuntu at:

```text
/mnt/c/Users/<WINDOWS_USERNAME>/Downloads/
```

For example:

```text
/mnt/c/Users/YTECH/Downloads/
```

You can verify the file exists with:

```bash
ls /mnt/c/Users/<WINDOWS_USERNAME>/Downloads/
```

For example:

```bash
ls /mnt/c/Users/YTECH/Downloads/
```

You should see:

```text
zkp-recovery-app-linux-beta.tar.gz
```

---

# 11. Extract the Application into the Linux Filesystem

It is recommended to run the application from the native WSL Linux filesystem rather than directly from `/mnt/c`.

Create a directory:

```bash
mkdir -p ~/zkp-recovery
```

Enter it:

```bash
cd ~/zkp-recovery
```

Extract the archive:

```bash
tar -xvf /mnt/c/Users/<WINDOWS_USERNAME>/Downloads/zkp-recovery-app-linux-beta.tar.gz
```

For example:

```bash
tar -xvf /mnt/c/Users/YTECH/Downloads/zkp-recovery-app-linux-beta.tar.gz
```

---

# 12. Check the Extracted Files

Run:

```bash
ls -la
```

Depending on how the release archive was packaged, you should see the application executable and its supporting files/directories.

For example:

```text
zkp_recovery_app
lib/
data/
```

or the archive may contain a `bundle/` directory:

```text
bundle/
```

If there is a `bundle` directory, enter it:

```bash
cd bundle
```

Then check:

```bash
ls -la
```

> **Important:** Keep the complete application bundle together. The `zkp_recovery_app` executable requires its accompanying libraries and application data.

---

# 13. Make the Application Executable

Run:

```bash
chmod +x zkp_recovery_app
```

Verify:

```bash
ls -l zkp_recovery_app
```

The executable permissions should include `x`, for example:

```text
-rwxr-xr-x
```

---

# 14. Run the ZKP Recovery App

From the directory containing `zkp_recovery_app`, run:

```bash
./zkp_recovery_app
```

If WSL2 and WSLg are configured correctly, the ZKP Recovery App window should appear directly on the Windows desktop.

> Do not run the application using `sudo` unless specifically required.

---

# Running the App Again Later

You do not need to repeat the installation process.

Open Ubuntu from the Windows Start menu, or run:

```cmd
wsl -d Ubuntu-24.04
```

Then:

```bash
cd ~/zkp-recovery
```

If the executable is directly in this directory:

```bash
./zkp_recovery_app
```

If the archive contains a `bundle` directory:

```bash
cd ~/zkp-recovery/bundle
./zkp_recovery_app
```

---

# Troubleshooting

## `sudo` Is Not Recognized

If you see:

```text
'sudo' is not recognized as an internal or external command
```

you are running the command from Windows Command Prompt.

For example:

```text
C:\Users\YTECH>sudo apt update
```

is incorrect.

Start Ubuntu:

```cmd
wsl -d Ubuntu-24.04
```

Then run:

```bash
sudo apt update
```

---

## `$` Is Not Recognized

If you see:

```text
'$' is not recognized as an internal or external command
```

you probably copied the shell prompt together with the command.

Do not run:

```text
$ sudo apt update
```

Run:

```bash
sudo apt update
```

---

## `wsl --set-default-version 2` Displays Help

On some systems, the initially installed WSL components may not recognize:

```cmd
wsl --set-default-version 2
```

You may see only:

```text
Usage: wsl.exe [Argument]
```

Install/enable WSL and Ubuntu first:

```cmd
wsl --install -d Ubuntu-24.04
```

Restart Windows if requested.

Then verify the installed distribution with:

```cmd
wsl -l -v
```

Make sure Ubuntu shows:

```text
VERSION
2
```

---

## `wsl --status` Produces No Output

If:

```cmd
wsl --status
```

returns nothing on a fresh Windows setup, continue with:

```cmd
wsl --install -d Ubuntu-24.04
```

Windows may need to enable the WSL components first.

Restart Windows when requested and complete the Ubuntu installation afterward.

---

## `tar: Cannot utime: Operation not permitted`

If you extract the archive directly inside the Windows filesystem:

```text
/mnt/c/Users/<WINDOWS_USERNAME>/Downloads/
```

you may see warnings such as:

```text
tar: ./lib/libdartjni.so: Cannot utime: Operation not permitted
tar: ./lib/libmopro_flutter_bindings.so: Cannot utime: Operation not permitted
tar: ./zkp_recovery_app: Cannot utime: Operation not permitted
```

This occurs because `/mnt/c` is a Windows-mounted filesystem and does not behave exactly like the native Linux filesystem for Linux permissions and timestamps.

Instead, extract the application into your WSL home directory:

```bash
mkdir -p ~/zkp-recovery
cd ~/zkp-recovery
```

Then:

```bash
tar -xvf /mnt/c/Users/<WINDOWS_USERNAME>/Downloads/zkp-recovery-app-linux-beta.tar.gz
```

---

## Permission Denied When Starting the App

If:

```bash
./zkp_recovery_app
```

returns:

```text
Permission denied
```

make the file executable:

```bash
chmod +x zkp_recovery_app
```

Then try again:

```bash
./zkp_recovery_app
```

---

## GUI Does Not Open

First verify that WSLg itself works:

```bash
gnome-text-editor
```

If GNOME Text Editor opens but the ZKP Recovery App does not, run:

```bash
./zkp_recovery_app
```

from the terminal again and check the terminal output for missing libraries or application-specific errors.

If GNOME Text Editor also fails to open, troubleshoot the WSLg installation before troubleshooting the ZKP Recovery App.

---

# Quick Start for Existing WSL2 Users

If WSL2 and Ubuntu 24.04 are already configured and the archive is in Windows Downloads:

```bash
mkdir -p ~/zkp-recovery
cd ~/zkp-recovery

tar -xvf /mnt/c/Users/<WINDOWS_USERNAME>/Downloads/zkp-recovery-app-linux-beta.tar.gz

chmod +x zkp_recovery_app

./zkp_recovery_app
```

For example:

```bash
mkdir -p ~/zkp-recovery
cd ~/zkp-recovery

tar -xvf /mnt/c/Users/YTECH/Downloads/zkp-recovery-app-linux-beta.tar.gz

chmod +x zkp_recovery_app

./zkp_recovery_app
```

If the release archive contains a `bundle/` directory instead, enter that directory before running the executable.

---

# Additional Documentation

For building the ZKP Recovery App **from source** instead of running the pre-built binary, refer to the Linux/WSL build instructions.

For more information about WSL and Linux GUI applications, see the official Microsoft WSL documentation.
