use super::*;
use std::{vec, vec::Vec};

#[test]
fn packed444_dimensions_and_limits() {
    let g = Geometry::new(2304, 1496).unwrap();
    assert_eq!(g.coded(), (2304, 2992));
    let rate = 827_228_160;
    let limits = Limits {
        max_width: 2304,
        max_height: 2992,
        max_pixels_per_second: rate,
    };
    assert!(limits.accepts(g, 120));
    assert!(!Limits {
        max_pixels_per_second: rate - 1,
        ..limits
    }
    .accepts(g, 120));
    assert!(!Limits::default().accepts(g, 120));
    for (w, h) in [(0, 1), (1, 0), (16385, 8), (64, 8193), (u32::MAX, 1)] {
        assert!(Geometry::new(w, h).is_none());
    }
}

#[test]
fn packed444_is_a_bijection_with_edge_padding() {
    for (w, h) in [(1, 1), (3, 5), (65, 9), (127, 17), (64, 8)] {
        let g = Geometry::new(w, h).unwrap();
        let n = (w * h) as usize;
        for max in [255, 1023] {
            let src: Vec<u16> = (0..3 * n)
                .map(|i| ((17 * i + 91 * (i / w as usize)) & max) as u16)
                .collect();
            let mut packed = vec![65535; g.samples()];
            assert!(g.pack([&src[..n], &src[n..2 * n], &src[2 * n..]], &mut packed));
            let mut seen = vec![false; g.samples()];
            for (p, plane) in [Plane::Y, Plane::U, Plane::V].into_iter().enumerate() {
                let (pw, ph) = g.padded();
                for y in 0..ph {
                    for x in 0..pw {
                        let i = g.index(g.address(plane, x, y).unwrap());
                        assert!(!seen[i]);
                        seen[i] = true;
                        assert_eq!(
                            packed[i],
                            src[p * n + (y.min(h - 1) * w + x.min(w - 1)) as usize]
                        );
                    }
                }
            }
            assert!(seen.into_iter().all(|x| x));
            let mut restored = vec![0; 3 * n];
            assert!(g.unpack(&packed, &mut restored));
            assert_eq!(src, restored);
            assert!(!g.unpack(&packed[..packed.len() - 1], &mut restored));
        }
    }
}

#[test]
fn packed444_vectors_pin_plane_parity() {
    let g = Geometry::new(3, 2).unwrap();
    // Fixed offsets keep plane parity independent of the roundtrip oracle.
    let vectors = [
        (Plane::Y, 2, 1, 66),
        (Plane::U, 0, 1, 1056),
        (Plane::V, 2, 1, 1313),
        (Plane::U, 1, 0, 512),
        (Plane::V, 1, 1, 608),
    ];
    for (p, x, y, index) in vectors {
        assert_eq!(g.index(g.address(p, x, y).unwrap()), index);
    }
}

#[test]
fn packed444_wire_rejects_unknown_or_inconsistent_layouts() {
    let packing = Packing(Geometry::new(65, 9).unwrap());
    let b = packing.encode();
    assert_eq!(Packing::decode(&b), Some(packing));
    for i in [0, 9, 13] {
        let mut bad = b;
        bad[i] ^= 2;
        assert_eq!(Packing::decode(&bad), None);
    }
    assert_eq!(Packing::decode(&b[..16]), None);
    let caps = Capabilities {
        versions: 1,
        modes: AV1_8,
        limits: Limits {
            max_width: 128,
            max_height: 32,
            max_pixels_per_second: 491520,
        },
    };
    assert_eq!(Capabilities::decode(&caps.encode()), Some(caps));
    assert!(caps.accepts(packing.0, 120, AV1_8));
    assert!(!caps.accepts(packing.0, 120, AV1_10));
    assert!(!caps.accepts(packing.0, 121, AV1_8));
}
