# Set up Roam Control

Follow these steps in order. Your iPhone will ask you to approve installation, enable Developer Mode, allow the VPN, and use a pairing record for this device.

1. **Download the IPA.** Open the [latest Roam Control release](https://github.com/Ayanshxkeel/roam-control-ios/releases/tag/v2.0.0-beta.1) and download **Roam-Control-Final.ipa** from Assets.
2. **Sign and install.** With your iPhone unlocked and connected to your computer, open [iloader](https://github.com/nab138/iloader/releases), select **Import IPA**, choose the file you downloaded, and follow the prompts. If SideStore is already configured, use it to install the IPA instead.
3. **Enable Developer Mode.** On your iPhone, open **Settings → Privacy & Security → Developer Mode** if it is off. Restart and confirm when iOS prompts you.
4. **Connect LocalDevVPN.** Install [LocalDevVPN](https://apps.apple.com/app/id6755608044), open it, and approve the VPN connection. Connect to Wi-Fi for the initial test.
5. **Pair this iPhone.** Open Roam Control and tap the setup icon. Choose **Import with SideStore** if your SideStore has a pairing record or **Choose Pairing File** if you already have a compatible remote-pairing record for this iPhone. See the [SideStore installation guide](https://docs.sidestore.io/docs/installation/install.html) for its setup. Keep your pairing file private.
6. **Verify setup.** In Roam Control’s setup screen, check the status of **Pairing Record**, **LocalDevVPN**, and **Developer Support**. Try a fixed pin first, then tap **Stop & Restore**.

Free signing can require regular refreshes. If a step fails, report your iOS version, installation method, and the exact error. This beta has primarily been tested on one iPhone setup, so device compatibility and background behavior can vary.
