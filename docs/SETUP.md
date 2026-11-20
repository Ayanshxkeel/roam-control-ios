# Download and run Roam Control on your iPhone

Allow time for the first setup. You will need your iPhone, a compatible computer, a USB cable, an Apple Account, and internet access. The current release is an iPhone beta. Installation and background behavior can vary by device and iOS version.

## 1. Download the app file

On your computer, open the [Roam Control release page](https://github.com/Ayanshxkeel/roam-control-ios/releases/tag/v2.0.0-beta.1).

1. Scroll to **Assets** and expand it.
2. Download **Roam-Control-Final.ipa**.
3. Keep it in Downloads so you can find it in the installer.

The Source code ZIP and TAR files are for developers. Choose the **.ipa** file to install the app.

## Download and open iloader on your Mac

1. Click the [official iloader Mac installer download](https://github.com/nab138/iloader/releases/latest/download/iloader-darwin-universal.dmg).
2. If your browser asks permission to download, click **Allow**.
3. Wait for the download to finish, then open **Finder → Downloads**.
4. Double-click **iloader-darwin-universal.dmg**.
5. Drag **iloader** into **Applications**. If the installer window has no Applications shortcut, drag the app onto **Applications** in Finder’s sidebar.
6. Open **Finder → Applications** and double-click **iloader**.
7. If macOS asks whether to open the downloaded app, click **Open**. If a different security message appears, check the [official iloader instructions](https://github.com/nab138/iloader#readme).
8. If iloader offers an update, install it and reopen iloader.

For Windows or Linux, select the appropriate installer from the [official iloader releases page](https://github.com/nab138/iloader/releases).

## 2. Install SideStore and prepare this iPhone

For a first-time user, SideStore provides a way to install and refresh the app and to supply its pairing record.

1. Follow the [official SideStore prerequisites](https://docs.sidestore.io/docs/installation/prerequisites.html) for your computer.
2. Download iloader from the official link in that guide and open it.
3. Connect your iPhone by USB, unlock it, and approve **Trust This Computer** if prompted.
4. Follow the [SideStore installation guide](https://docs.sidestore.io/docs/installation/install.html), including its Apple Account, trust, pairing, VPN, and first refresh steps.
5. Confirm SideStore opens and refreshes successfully before continuing.

Enter your password and verification codes directly into the installer or SideStore when requested. Each user needs a pairing record created for their own iPhone.

If you already have SideStore working on this iPhone, you can skip to the next step.

## 3. Install Roam Control

Using iloader on your computer:

1. Keep the iPhone connected and unlocked.
2. Select your iPhone in iloader.
3. Click **Import IPA**.
4. Choose **Roam-Control-Final.ipa** from Downloads.
5. Follow the signing and installation prompts.
6. Wait for iloader to report success.
7. Find **Roam Control** in the iPhone’s App Library.

Alternatively, if SideStore is already configured, transfer the IPA to the iPhone’s Files app, open SideStore, and use its import/install control to select the IPA.

## 4. Enable Developer Mode and trust the installation

1. On the iPhone, open **Settings → Privacy & Security → Developer Mode**.
2. Turn it on if it is off.
3. Restart if prompted, unlock the phone, and confirm **Turn On**.
4. If iOS reports an untrusted developer, open **Settings → General → VPN & Device Management**, select the developer entry for your signing account, and complete the trust prompt.
5. Open Roam Control again.

If Developer Mode is absent, complete the developer-app installation and check the official SideStore troubleshooting instructions before continuing.

## 5. Connect LocalDevVPN

1. Install [LocalDevVPN from the App Store](https://apps.apple.com/app/id6755608044) if you have not already.
2. Open it, choose **Connect**, and approve the VPN configuration prompt.
3. Keep it connected.
4. Use Wi-Fi for the first setup and fixed-pin test.

Roam Control uses this local connection to reach the iPhone’s developer service.

## 6. Import this iPhone’s pairing record

1. Open Roam Control and tap the setup/settings icon.
2. Choose **Import with SideStore**.
3. Approve opening SideStore and returning to Roam Control if prompted.
4. Wait for the import to finish.

If you already have a compatible remote-pairing file for this exact iPhone in Files, use **Choose Pairing File** instead. A pairing file contains private device credentials. Keep it out of screenshots, public repositories, and support reports.

The setup screen shows **Pairing Record**, **LocalDevVPN**, and **Developer Support**. Follow any preparation prompts and wait until the device is ready.

## 7. Try a fixed location first

1. Search for a place or drop a pin on the map.
2. Tap **Start location**.
3. Wait for the active simulation status.
4. Check the location in Apple Maps on the same iPhone.
5. Return to Roam Control and tap **Stop & Restore**.
6. Confirm the phone reports its real location again.

If the fixed pin fails, resolve setup before starting a moving route.

## 8. Start a moving route

1. Start a fixed pin at your desired origin if you want the trip to begin there.
2. Select the destination on the main map.
3. Expand **Route planning**. The active simulated location is the default origin, and the selected pin is the destination.
4. Choose **Driving**, **Walking**, or **Cycling**.
5. Set the departure time and review the speed settings.
6. Tap **Preview route** and inspect the route on the map.
7. Tap **Start driving**, **Start walking**, or **Start cycling**.
8. For a future departure, choose **Keep my real location** or **Hold the route origin**.
9. Use **Pause / Resume** during playback or **Stop & Restore** to end it.

For driving, **Speed** is an offset above the road baseline. A +0 offset follows the baseline; +10 adds 10 km/h. Missing limits use 40 km/h. Pace changes for acceleration, braking, and turns. The app does not use live traffic-light states.

Verify behavior on your own device before relying on long departures or locked-screen playback. Another app may display a delayed or cached location.

## Updates and signing refresh

Install a newer IPA over the existing app using the same signing account to retain app data where possible. Free-account signing generally requires refreshing within seven days. Follow your installer’s expiry indicator and refresh instructions.

## If something goes wrong

| Problem | What to check |
| --- | --- |
| IPA downloaded but app missing | Finish signing and installation in iloader or SideStore. Downloading alone does not install an iPhone app. |
| App will not open | Check developer trust, Developer Mode, and signing expiry. |
| Pairing import fails | Use a current remote-pairing record for this exact iPhone and confirm SideStore works. |
| InvalidUtf8AsciiStream or another parsing error | Record the exact error and how you imported the pairing record. Do not upload the pairing file. |
| Start location or route fails | Check LocalDevVPN, the setup status, and a fixed pin first. |
| Another app shows an old pin | Allow it time to refresh. Confirm the current location in Apple Maps on the same phone. |
| Real location does not return | Use Stop & Restore. If restoration cannot be confirmed, disconnect LocalDevVPN or restart the phone, then check again. |

Report your iOS version, installation method, connection type, and exact error in [GitHub Issues](https://github.com/Ayanshxkeel/roam-control-ios/issues).
