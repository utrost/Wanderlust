//! Small geodesy helpers. City-scale, so we use a local equirectangular
//! projection (metres relative to a reference latitude) for planar distance
//! work, and haversine where true great-circle distance matters.

/// Mean Earth radius, metres.
pub const EARTH_RADIUS_M: f64 = 6_371_000.0;

/// A WGS84 coordinate. `lng`/`lat` in degrees.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LngLat {
    pub lng: f64,
    pub lat: f64,
}

impl LngLat {
    pub fn new(lng: f64, lat: f64) -> Self {
        Self { lng, lat }
    }

    /// Project to local metres about `ref_lat_rad` (equirectangular). Good to a
    /// fraction of a percent across a city; not for continental spans.
    pub fn to_xy(self, ref_lat_rad: f64) -> (f64, f64) {
        let x = EARTH_RADIUS_M * self.lng.to_radians() * ref_lat_rad.cos();
        let y = EARTH_RADIUS_M * self.lat.to_radians();
        (x, y)
    }
}

/// Great-circle distance between two coordinates, in metres.
pub fn haversine_m(a: LngLat, b: LngLat) -> f64 {
    let (lat1, lat2) = (a.lat.to_radians(), b.lat.to_radians());
    let dlat = (b.lat - a.lat).to_radians();
    let dlng = (b.lng - a.lng).to_radians();
    let h = (dlat / 2.0).sin().powi(2) + lat1.cos() * lat2.cos() * (dlng / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * h.sqrt().asin()
}

/// Distance in metres from point `p` to the line segment `a`–`b`, all projected
/// about `ref_lat_rad`. Returns the perpendicular distance to the segment,
/// clamped to its endpoints.
pub fn point_to_segment_m(p: LngLat, a: LngLat, b: LngLat, ref_lat_rad: f64) -> f64 {
    let (px, py) = p.to_xy(ref_lat_rad);
    let (ax, ay) = a.to_xy(ref_lat_rad);
    let (bx, by) = b.to_xy(ref_lat_rad);

    let (abx, aby) = (bx - ax, by - ay);
    let ab2 = abx * abx + aby * aby;
    let t = if ab2 <= f64::EPSILON {
        0.0
    } else {
        (((px - ax) * abx + (py - ay) * aby) / ab2).clamp(0.0, 1.0)
    };
    let (cx, cy) = (ax + t * abx, ay + t * aby);
    ((px - cx).powi(2) + (py - cy).powi(2)).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn haversine_known_distance() {
        // ~111 km per degree of latitude.
        let d = haversine_m(LngLat::new(13.4, 52.5), LngLat::new(13.4, 53.5));
        assert!((d - 111_195.0).abs() < 500.0, "got {d}");
    }

    #[test]
    fn point_on_segment_is_zero() {
        let r = 52.5_f64.to_radians();
        let a = LngLat::new(13.40, 52.50);
        let b = LngLat::new(13.41, 52.50);
        let mid = LngLat::new(13.405, 52.50);
        assert!(point_to_segment_m(mid, a, b, r) < 0.5);
    }

    #[test]
    fn point_off_segment_measures_perpendicular() {
        let r = 52.5_f64.to_radians();
        let a = LngLat::new(13.40, 52.50);
        let b = LngLat::new(13.41, 52.50);
        // ~111 m north of the segment midpoint.
        let off = LngLat::new(13.405, 52.501);
        let d = point_to_segment_m(off, a, b, r);
        assert!((d - 111.0).abs() < 10.0, "got {d}");
    }
}
