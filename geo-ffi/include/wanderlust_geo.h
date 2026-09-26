/*
 * wanderlust_geo.h — C ABI for Wanderlust's geo-core (see geo-ffi/src/ffi.rs).
 *
 * The Flutter app binds these via dart:ffi (ADR-0003). JSON in/out keeps the
 * boundary stable. Ownership:
 *   - matcher handles come from wanderlust_matcher_from_geojson, freed with
 *     wanderlust_matcher_free.
 *   - returned strings are owned by the caller, freed with wanderlust_string_free.
 * All functions are null-safe and never unwind across the boundary.
 */
#ifndef WANDERLUST_GEO_H
#define WANDERLUST_GEO_H

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque loaded street network for one area. */
typedef struct Matcher Matcher;

/* Build a matcher from a GeoJSON street network. Returns NULL on bad input. */
Matcher *wanderlust_matcher_from_geojson(const char *geojson);

/* Free a matcher handle. */
void wanderlust_matcher_free(Matcher *matcher);

/*
 * Match a GPX track against the network. Returns an owned JSON string:
 *   {"walked":[id,...],"gaps_filled":n,"gaps_rejected":n}
 * or {"error":"description"} for invalid GPX. NULL denotes invalid pointers
 * or an internal failure. Free non-NULL strings with wanderlust_string_free.
 */
char *wanderlust_match_gpx(Matcher *matcher, const char *gpx);

/* Free a string returned by this library. */
void wanderlust_string_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* WANDERLUST_GEO_H */
