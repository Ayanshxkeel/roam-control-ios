# Build 24: map mode switch and dismissible Community notice

The original map remains mounted in both modes. Regular map and Community map buttons sit in its top safe-area inset, below the navigation search field. Community is selected on a fresh launch. Existing opt-in and owner-exemption rules remain unchanged: default selection does not enroll the user, upload location, or grant access to community pins. Unenrolled users see a join/access notice and the normal map features. Tapping Community when not enrolled opens the consent screen again. Revoked access removes pins while retaining the Community mode shell.

The informational Community notice can be swiped upward. It follows the finger, accepts an upward flick, springs back on a short release and animates offscreen on dismissal. An X and accessibility dismiss action are also available. Reduce Motion skips the offscreen exit animation. Banner dismissal leaves mode buttons and shared pins intact. Choosing Community again restores the notice. The mode buttons do not themselves change location-sharing consent.

Release compilation and whitespace checks passed. Installed-iPhone validation is still required for under-search positioning on different screen sizes, swipe threshold/flick smoothness, short-swipe return, accessibility, and switching modes during active driving.
