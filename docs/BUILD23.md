# Build 23: recenter and smaller custom pins

A local recenter button sits directly beneath the 2D/3D pitch toggle on the map. If a simulation is active, it centers on the app's current spoof coordinate immediately. Otherwise it requests one fresh device-reported location using When In Use permission. Permission denial, restricted access and a 20-second timeout show an explanatory error. Recenter does not change the selected destination, teleport the device, cancel a route or change sharing preferences. It turns off the driving follow camera for the manual camera move. The next render uses the current spoof if one started while a GPS request was pending. The local locator never sends coordinates to the backend; separately consented sharing remains independent.

Custom symbol font size is 18 points, down from 36. Glow radius, depth offsets and padding are also halved. A 44-point transparent interaction frame remains for accessibility and dragging. The selected symbol is anchored at its center on the selected map coordinate. Community profile photos are unchanged.

Validation: Release compilation and source whitespace checks. On-device testing still needed for exact control placement, permission denial, stationary and moving spoof recentering, 2D/3D orientation, and touch-target comfort.
