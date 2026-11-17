# Roam Control

Roam Control is an iPhone location simulation app for testing on a device you own or control. It supports fixed pins and timed walking, cycling, and driving routes.

**[Set up Roam Control](docs/SETUP.md)** · **[Download the latest beta](https://github.com/Ayanshxkeel/roam-control-ios/releases/tag/v2.0.0-beta.1)**

This release is an unsigned iPhone IPA. The setup guide walks through signing, installation, and the approvals required on each iPhone.

## Build from source

Install Xcode and XcodeGen on a Mac. From this checkout:

```sh
bash scripts/fetch-idevice.sh
xcodegen generate
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Open the generated Xcode project and select your own signing team to build for a personal device. The pinned dependency download verifies its checksums. See [the upstream documentation](docs/UPSTREAM.md) for implementation details and [the third-party notices](THIRD_PARTY_NOTICES.md) for dependency notices.

## Credits and license

This is an independently maintained fork of [WaypointApp by raph559](https://github.com/raph559/WaypointApp), licensed under the [GNU AGPL v3.0](LICENSE). This project is unaffiliated with the separately developed app of the same name.
