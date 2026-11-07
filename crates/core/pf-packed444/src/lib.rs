//! Sample layout shared by packed-video producers and consumers.
//!
//! Version 1 carries three full-size planes in a double-height 4:2:0 picture.
//! Geometry describes samples, independently of colour conversion and codec loss.
//! See `docs/adr/0003-packed444.md` for the wire contract and reference provenance.

#![no_std]

pub const VERSION: u8 = 1;
pub const HEVC8: u8 = 1;
pub const HEVC10: u8 = 2;
pub const AV1_8: u8 = 4;
pub const AV1_10: u8 = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Geometry {
    width: u32,
    height: u32,
    padded_width: u32,
    padded_height: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Plane {
    Y,
    U,
    V,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Address {
    pub plane: Plane,
    pub x: u32,
    pub y: u32,
}

impl Geometry {
    pub fn new(width: u32, height: u32) -> Option<Self> {
        if width == 0 || height == 0 || width > 16384 || height > 8192 {
            return None;
        }
        Some(Self {
            width,
            height,
            padded_width: width.div_ceil(64) * 64,
            padded_height: height.div_ceil(8) * 8,
        })
    }

    pub const fn source(self) -> (u32, u32) {
        (self.width, self.height)
    }
    pub const fn padded(self) -> (u32, u32) {
        (self.padded_width, self.padded_height)
    }
    pub const fn coded(self) -> (u32, u32) {
        (self.padded_width, 2 * self.padded_height)
    }
    pub const fn samples(self) -> usize {
        3 * self.padded_width as usize * self.padded_height as usize
    }

    /// An original sample's address in the decoded planar 4:2:0 picture.
    pub fn address(self, plane: Plane, x: u32, y: u32) -> Option<Address> {
        if x >= self.padded_width || y >= self.padded_height {
            return None;
        }
        Some(match plane {
            Plane::Y => Address {
                plane: Plane::Y,
                x,
                y,
            },
            Plane::U | Plane::V if x & 1 == 0 => Address { plane, x: x / 2, y },
            _ => Address {
                plane: Plane::Y,
                x: x / 2
                    + if plane == Plane::V {
                        self.padded_width / 2
                    } else {
                        0
                    },
                y: self.padded_height + y,
            },
        })
    }

    pub fn index(self, address: Address) -> usize {
        let w = self.padded_width as usize;
        let h = self.padded_height as usize;
        let x = address.x as usize;
        let y = address.y as usize;
        match address.plane {
            Plane::Y => y * w + x,
            Plane::U => 2 * w * h + y * w / 2 + x,
            Plane::V => 2 * w * h + w * h / 2 + y * w / 2 + x,
        }
    }

    /// Dense planar reference only; GPU paths use addresses without CPU frame copies.
    pub fn pack<T: Copy>(self, source: [&[T]; 3], destination: &mut [T]) -> bool {
        let n = (self.width * self.height) as usize;
        if source.iter().any(|s| s.len() != n) || destination.len() != self.samples() {
            return false;
        }
        for (plane, data) in [Plane::Y, Plane::U, Plane::V].into_iter().zip(source) {
            for y in 0..self.padded_height {
                for x in 0..self.padded_width {
                    let src =
                        (y.min(self.height - 1) * self.width + x.min(self.width - 1)) as usize;
                    let a = self.address(plane, x, y).unwrap();
                    destination[self.index(a)] = data[src];
                }
            }
        }
        true
    }

    pub fn unpack<T: Copy>(self, packed: &[T], destination: &mut [T]) -> bool {
        let n = (self.width * self.height) as usize;
        if packed.len() != self.samples() || destination.len() != 3 * n {
            return false;
        }
        for (p, plane) in [Plane::Y, Plane::U, Plane::V].into_iter().enumerate() {
            for y in 0..self.height {
                for x in 0..self.width {
                    let a = self.address(plane, x, y).unwrap();
                    destination[p * n + (y * self.width + x) as usize] = packed[self.index(a)];
                }
            }
        }
        true
    }
}

/// A zero limit is unknown, so it never proves a mode is safe.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Limits {
    pub max_width: u32,
    pub max_height: u32,
    pub max_pixels_per_second: u64,
}

impl Limits {
    pub fn accepts(self, geometry: Geometry, fps: u32) -> bool {
        let (w, h) = geometry.coded();
        fps > 0
            && w <= self.max_width
            && h <= self.max_height
            && u64::from(w) * u64::from(h) * u64::from(fps) <= self.max_pixels_per_second
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Capabilities {
    pub versions: u8,
    pub modes: u8,
    pub limits: Limits,
}

impl Capabilities {
    pub fn accepts(self, geometry: Geometry, fps: u32, mode: u8) -> bool {
        self.versions & 1 != 0
            && mode.count_ones() == 1
            && mode & 15 != 0
            && self.modes & mode != 0
            && self.limits.accepts(geometry, fps)
    }

    pub fn encode(self) -> [u8; 18] {
        let mut b = [0; 18];
        b[0] = self.versions;
        b[1] = self.modes;
        b[2..6].copy_from_slice(&self.limits.max_width.to_le_bytes());
        b[6..10].copy_from_slice(&self.limits.max_height.to_le_bytes());
        b[10..18].copy_from_slice(&self.limits.max_pixels_per_second.to_le_bytes());
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() != 18 {
            return None;
        }
        Some(Self {
            versions: b[0],
            modes: b[1],
            limits: Limits {
                max_width: u32::from_le_bytes(b[2..6].try_into().ok()?),
                max_height: u32::from_le_bytes(b[6..10].try_into().ok()?),
                max_pixels_per_second: u64::from_le_bytes(b[10..18].try_into().ok()?),
            },
        })
    }
}

/// The epoch's sample layout; bit depth and CICP remain in the video format.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Packing(pub Geometry);

impl Packing {
    pub fn encode(self) -> [u8; 17] {
        let mut b = [0; 17];
        b[0] = VERSION;
        let (w, h) = self.0.source();
        let (cw, ch) = self.0.coded();
        for (bytes, value) in b[1..].chunks_exact_mut(4).zip([w, h, cw, ch]) {
            bytes.copy_from_slice(&value.to_le_bytes());
        }
        b
    }

    pub fn decode(b: &[u8]) -> Option<Self> {
        if b.len() != 17 || b[0] != VERSION {
            return None;
        }
        let mut words = [0; 4];
        for (value, bytes) in words.iter_mut().zip(b[1..].chunks_exact(4)) {
            *value = u32::from_le_bytes(bytes.try_into().ok()?);
        }
        let geometry = Geometry::new(words[0], words[1])?;
        (geometry.coded() == (words[2], words[3])).then_some(Self(geometry))
    }
}

#[cfg(test)]
extern crate std;
#[cfg(test)]
mod tests;
