# Walk review and map labels

Open **Saved walks**, then tap a walk. The review map fits its recorded trace.
Three independent toggles show:

- **GPS trace**: blue recorded readings. Separate GPX segments, non-increasing
  timestamps and gaps over 30 seconds break the line. Untimed GPX segments retain
  their own boundaries. This is recorded GPS, not a claim of the exact path taken.
- **Matched streets**: brown sections supported directly by the matcher.
- **Inferred gaps**: purple dashed sections supported only by route inference,
  including the original automatic fill and the optional short-gap pass.

**Preview gap filling** starts with the saved preference but affects this review
only. It never writes preferences, raw walks or coverage. Matching runs in a
worker isolate across saved maps; direct support takes precedence over inference
when maps or GPX segments overlap. The main coverage colours/counts are unchanged.
If matching fails, the raw trace remains available and Retry reruns matching.
Areas outside saved maps retain their GPS trace and show a notice. Empty walks
show an explicit message. GPX export remains beside each saved walk.

## Offline labels

Street names already in map files now render at walking scale (about 2 km or
less visible span). Text stays screen-sized, honours text scaling, and uses
collision checks, name/edge deduplication and a 35-label viewport cap. Visible
pieces of a named street are considered together so short split sections can
still receive a label. No online tiles, geocoder or extra location lookup.

New downloads and **Offline maps → Refresh** also request named settlement nodes
within the same map bounds from Overpass. Named parks and waterways use the
already downloaded scenery data. These labels are stored separately from the
street graph. The network version and stable edge IDs exclude decorative labels;
refreshing metadata alone does not detach old coverage.

Downloaded area names use “Around <nearest place> · <size>”, with a nearby named
street fallback, then the existing coordinates if neither is available. “Around”
is intentional: the map is a square around its requested centre, not an official
neighbourhood boundary. Existing downloaded titles change when refreshed;
custom titles supplied to the normalizer are preserved.

## Validation

Native tests cover direct/inferred provenance, including default fill and direct
support overriding earlier inference. Flutter tests cover native review, raw
trace preservation, layer switches, preview retry, segment/outage boundaries,
place extraction, stable IDs/version, malformed optional labels, collision and
viewport rules, and labels on short street geometry. A 420 × 880 rendered Bremen
review was visually inspected for trace fitting, label density and layer contrast.
No real-phone review or label acceptance is claimed yet.
