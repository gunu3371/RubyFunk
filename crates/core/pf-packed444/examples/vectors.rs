use pf_packed444::{Geometry, Packing};
use std::{env, fs, path::Path};

fn main() -> std::io::Result<()> {
    let destination = env::args().nth(1).expect("vector output directory");
    fs::create_dir_all(&destination)?;
    for (w, h) in [(1, 1), (3, 2), (65, 9)] {
        for depth in [8u8, 10] {
            let geometry = Geometry::new(w, h).unwrap();
            let n = (w * h) as usize;
            let mask = (1usize << depth) - 1;
            let source: Vec<u16> = (0..3 * n)
                .map(|i| ((i * 313 + (i / w as usize) * 71) & mask) as u16)
                .collect();
            let mut packed = vec![0u16; geometry.samples()];
            assert!(geometry.pack(
                [&source[..n], &source[n..2 * n], &source[2 * n..]],
                &mut packed
            ));
            let mut bytes = b"RF44".to_vec();
            bytes.extend_from_slice(&[
                depth,
                if depth == 10 { 9 } else { 1 },
                if depth == 10 { 16 } else { 1 },
                if depth == 10 { 9 } else { 1 },
                u8::from(w != 3),
                0,
                0,
                0,
            ]);
            bytes.extend_from_slice(&Packing(geometry).encode());
            for value in packed.into_iter().chain(source) {
                bytes.extend_from_slice(&value.to_le_bytes());
            }
            let name = format!("v1-{w}x{h}-{depth}.rf444");
            fs::write(Path::new(&destination).join(name), bytes)?;
        }
    }
    Ok(())
}
