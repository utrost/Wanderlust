//! The C ABI the Flutter app links against (ADR-0003). Deliberately tiny: build
//! a matcher from GeoJSON, run a GPX walk, get JSON back. JSON in/out keeps the
//! boundary trivial to bridge from Dart (`dart:ffi` + `jsonDecode`) and easy to
//! evolve without ABI churn.
//!
//! Ownership contract:
//! - `wanderlust_matcher_from_geojson` returns an owned handle; free it with
//!   `wanderlust_matcher_free`.
//! - `wanderlust_match_gpx` returns an owned C string; free it with
//!   `wanderlust_string_free`.
//! - All functions are null-safe and catch panics so nothing unwinds across FFI.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::catch_unwind;

use geo_core::MatchConfig;

use crate::api::Matcher;

/// Build a matcher from a GeoJSON street network. Returns null on bad input.
///
/// # Safety
/// `geojson` must be a valid NUL-terminated UTF-8 C string (or null).
#[no_mangle]
pub unsafe extern "C" fn wanderlust_matcher_from_geojson(geojson: *const c_char) -> *mut Matcher {
    let result = catch_unwind(|| {
        let src = cstr(geojson)?;
        Matcher::from_geojson(&src).ok()
    });
    match result {
        Ok(Some(m)) => Box::into_raw(Box::new(m)),
        _ => std::ptr::null_mut(),
    }
}

/// Free a matcher handle.
///
/// # Safety
/// `matcher` must have come from `wanderlust_matcher_from_geojson` and not been
/// freed already.
#[no_mangle]
pub unsafe extern "C" fn wanderlust_matcher_free(matcher: *mut Matcher) {
    if !matcher.is_null() {
        drop(Box::from_raw(matcher));
    }
}

/// Match a GPX track. Returns an owned JSON C string:
/// `{"walked":[id,...],"gaps_filled":n,"gaps_rejected":n}` or
/// `{"error":"description"}` for invalid GPX; null on invalid pointers/panic.
///
/// # Safety
/// `matcher` must be a live handle; `gpx` a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn wanderlust_match_gpx(
    matcher: *mut Matcher,
    gpx: *const c_char,
) -> *mut c_char {
    if matcher.is_null() {
        return std::ptr::null_mut();
    }
    let matcher = &*matcher;
    let gpx_owned = match cstr(gpx) {
        Some(s) => s,
        None => return std::ptr::null_mut(),
    };

    let json = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let result = match matcher.match_gpx(&gpx_owned, MatchConfig::default()) {
            Ok(result) => result,
            Err(message) => return serde_json::json!({"error": message}).to_string(),
        };
        let ids = matcher.walked_ids(&result);
        serde_json::json!({
            "walked": ids,
            "gaps_filled": result.gaps_filled,
            "gaps_rejected": result.gaps_rejected,
        })
        .to_string()
    }));

    match json.ok().and_then(|s| CString::new(s).ok()) {
        Some(c) => c.into_raw(),
        None => std::ptr::null_mut(),
    }
}

/// Free a string returned by this library.
///
/// # Safety
/// `s` must have come from a `wanderlust_*` function and not been freed already.
#[no_mangle]
pub unsafe extern "C" fn wanderlust_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// # Safety
/// `p` must be null or a valid NUL-terminated UTF-8 C string.
unsafe fn cstr(p: *const c_char) -> Option<String> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok().map(str::to_owned)
}
