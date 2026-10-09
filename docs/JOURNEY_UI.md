# Journey feedback and memories

The main map retains one Start/Stop flow. A small status surface appears only
while saved routes are actually being rematched, briefly confirms success after
persistence, and offers retry on failure. Live preview updates do not trigger
this notice, and a no-op synchronization does not announce completion.

After stopping, a brief message summarizes recording continuity. The same summary
is available in journey review with an expandable explanation. It measures saved
GPS timestamps, including acquisition delay and time before stopping. Intervals
longer than 30 seconds are reported as approximate total gap time; separate track
segments and interrupted recordings are not labelled continuous. Untimed imports,
summary-only data and recordings with fewer than two fixes report unknown quality.
Continuity is distinct from GPS accuracy and street-matching confidence.

Memories use lazily loaded photo/note cards. Saved memories open in a swipeable
reader with a full-screen, zoomable photo and an explicit Edit action. Drafts open
in the editor. Map pins use the same reader. Photo failures offer a retry rather
than silently presenting an empty memory. Card transitions and photo Hero effects
respect the platform's reduced-motion setting. Review controls scroll when space
or large text would otherwise squeeze out the map.

The small compass displays the direction the top of the screen faces, relative
to magnetic north. The map remains north-up. Unavailable or unreliable sensor
readings do not become a trusted heading. The native rotation-vector listener is
registered only with an active UI subscription and a resumed Android activity;
it unregisters on pause, cancellation and destruction. No permission, GPS request,
background service, or new third-party dependency is added. Display rotation is
handled using Android's coordinate remapping API, as documented in the
[Android position-sensor guide](https://developer.android.com/develop/sensors-and-location/sensors/sensors_position).
