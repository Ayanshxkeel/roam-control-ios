# Roam Control

Roam Control is an open-source iPhone app for testing location-based experiences on a device you own or control. Set a fixed location or run a simulated trip to see how an app behaves as the location changes, without physically traveling the route.

**[Download the iPhone beta](https://github.com/Ayanshxkeel/roam-control-ios/releases/tag/v2.0.0-beta.1)** · **[Set up Roam Control](docs/SETUP.md)**

## Download and run on your iPhone

1. Download **Roam-Control-Final.ipa** from the [release page](https://github.com/Ayanshxkeel/roam-control-ios/releases/tag/v2.0.0-beta.1).
2. Set up SideStore and LocalDevVPN using the linked installation guides.
3. Connect and unlock your iPhone, then use **Import IPA** in iloader to sign and install the download.
4. Enable Developer Mode, complete device pairing, and verify a fixed pin before running a route.

The [complete step-by-step setup guide](docs/SETUP.md) covers every stage, first launch, route playback, updates, and troubleshooting.

## Who it’s for

- **iOS developers** testing map pins, location-dependent screens, and changes in position.
- **QA testers** reproducing a trip, checking how an app handles a pause, or testing what happens when a session is interrupted.
- **Students and hobbyists** exploring route planning and location simulation on their own iPhones.

## What you can do

- **Test a fixed location.** Search for an address or drop a pin, hold that position, and use **Stop & Restore** to end the simulation.
- **Plan a walking, cycling, or driving trip.** Preview the route on the map, compare alternatives when available, and scrub through the trip before starting.
- **Schedule a departure.** Choose whether the phone should report its real location or hold the route origin while waiting. The planner includes a countdown and optional reminder.
- **Inspect driving pace.** The speed profile uses road limits where available, with a 40 km/h fallback for missing data. It models acceleration and braking for sharper turns and shows the estimated pace and arrival during playback.
- **Control and repeat a trip.** Pause, resume, add a timed stop, or retrace a completed route. Save a favorite pin, reuse recent trip settings, or prepare a new route from the last saved point after an interruption.

For example, a tester can preview a downtown drive, add a two-minute stop, and check how their map responds when movement resumes. They can repeat the same trip from **Recent routes**.

## What you need

The public beta is an unsigned iPhone IPA. Installation requires a signing tool such as iloader or SideStore, Developer Mode, LocalDevVPN, and a pairing record for your own iPhone. Follow the [guided setup](docs/SETUP.md), then verify a fixed pin and **Stop & Restore** before trying a route.

Compatibility and background behavior can vary by iOS version and device. Scheduled departures while the phone is locked are unverified. Speed limits can be incomplete, and the driving profile does not use live traffic signal states.

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
