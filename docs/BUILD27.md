# Build 27: compact map layout

- Shared-pin count/status/Refresh/Show pins panel now uses the same finger-following upward swipe dismissal as the Community notice. It remains dismissed through refreshes; pressing Community map again restores it. Shared pins and sharing consent are unaffected.
- Regular/Community switcher is about half the former height, with a compact 240-point maximum width. It uses native Liquid Glass on iOS 26+ and a translucent material fallback on earlier systems.
- Removed the map navigation title and Support button. A custom search row occupies the top map inset and retains Settings on its upper-right side. Search autocomplete, recent/favorite suggestions, clear, submit and keyboard dismissal remain connected to PlaceSearchController.
- Map appearance, route planning and profile controls now sit beneath recenter on the right. The column scrolls when the available map height is short. Compass and pitch remain above recenter. No profile button floats over the search row anymore; unread badge remains on the profile button.
- The route panel's text heading button is replaced by a small handle/chevron, retaining accessible expand/collapse behavior. Panel heights are reduced to 200 points collapsed and 420 expanded.

Release compilation and whitespace checks passed. Installed-iPhone verification is still required for exact search position, suggestion taps, keyboard behavior, glass rendering, right-column scrolling on short maps, swipe smoothness, dynamic text sizes and route controls.
