//! Turning a generated picture into a sprite.
//!
//! This is the half of the pipeline that does not involve a provider, and it is
//! the half that decides whether the result looks like a 1993 shooter or like a
//! photograph someone shrank.
//!
//! The order matters and is not arbitrary.
//!
//! 1. **Trim to the alpha bounding box.** A generator centres its subject in
//!    whatever canvas it likes. Trimming first means the downscale ratio is
//!    decided by the sprite, not by the empty space around it.
//! 2. **Downscale with a triangle filter.** Samples blend before quantisation;
//!    nearest-neighbour at this step would discard detail and introduce aliasing.
//! 3. **Quantise to the palette**, matched in CIE L\*a\*b\* rather than in RGB,
//!    because RGB distance does not match what an eye calls "the nearest
//!    colour" and picks visibly wrong swatches in dark and saturated regions.
//! 4. **Harden the alpha.** A sprite has no half-transparent edge. Anything
//!    ambiguous is pushed to fully on or fully off, which is what gives the
//!    silhouette its bite.
//!
//! Steps two and three are why the contract asks for generation at four times
//! the target: an exact integer ratio keeps the pixel grid square and aligned.

use std::path::Path;

use image::{imageops, GenericImageView, ImageBuffer, Rgba, RgbaImage};

use crate::Error;

/// Alpha at or below this is treated as empty when trimming.
const TRIM_ALPHA: u8 = 8;

/// Alpha above this becomes solid, at or below becomes empty.
const ALPHA_CUT: u8 = 128;

/// A colour in CIE L*a*b*.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Lab {
    pub l: f32,
    pub a: f32,
    pub b: f32,
}

/// sRGB to linear light. The 0.04045 knee is the sRGB transfer function.
fn srgb_to_linear(channel: u8) -> f32 {
    let c = f32::from(channel) / 255.0;
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// sRGB to CIE L*a*b* through XYZ, D65 white point.
pub fn to_lab(r: u8, g: u8, b: u8) -> Lab {
    let (rl, gl, bl) = (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b));

    let x = rl * 0.412_456_4 + gl * 0.357_576_1 + bl * 0.180_437_5;
    let y = rl * 0.212_672_9 + gl * 0.715_152_2 + bl * 0.072_175;
    let z = rl * 0.019_333_9 + gl * 0.119_192 + bl * 0.950_304_1;

    // D65 reference white.
    let (xn, yn, zn) = (0.950_49, 1.0, 1.088_84);
    let f = |t: f32| -> f32 {
        const DELTA: f32 = 6.0 / 29.0;
        if t > DELTA * DELTA * DELTA {
            t.cbrt()
        } else {
            t / (3.0 * DELTA * DELTA) + 4.0 / 29.0
        }
    };
    let (fx, fy, fz) = (f(x / xn), f(y / yn), f(z / zn));

    Lab {
        l: 116.0 * fy - 16.0,
        a: 500.0 * (fx - fy),
        b: 200.0 * (fy - fz),
    }
}

/// Squared distance in Lab. Squared because only the ordering is used.
pub fn lab_distance_squared(x: Lab, y: Lab) -> f32 {
    let (dl, da, db) = (x.l - y.l, x.a - y.a, x.b - y.b);
    dl * dl + da * da + db * db
}

/// A palette, held as RGB and as the Lab used to match against it.
#[derive(Debug, Clone)]
pub struct Palette {
    pub colours: Vec<[u8; 3]>,
    lab: Vec<Lab>,
}

impl Palette {
    pub fn new(colours: Vec<[u8; 3]>) -> Result<Self, Error> {
        if colours.is_empty() {
            return Err(Error::Spec("palette has no colours".into()));
        }
        let lab = colours.iter().map(|c| to_lab(c[0], c[1], c[2])).collect();
        Ok(Palette { colours, lab })
    }

    /// Read a palette file.
    ///
    /// Three shapes are accepted, because `docs/palette.json` was already a
    /// named map of RGBA arrays before this tool existed and renaming the
    /// project's palette to suit a new program would be the wrong way round.
    ///
    /// - `{"ink": [10, 10, 12, 255], ...}`, the repository's own format
    /// - `["#rrggbb", ...]`
    /// - `{"colours": [...]}` or `{"colors": [...]}` wrapping either of those
    ///
    /// An alpha component is read and discarded: quantisation decides colour,
    /// and the alpha of a sprite pixel comes from the sprite.
    pub fn from_json(text: &str) -> Result<Self, Error> {
        let value: serde_json::Value = serde_json::from_str(text)
            .map_err(|e| Error::Spec(format!("palette is not valid json: {e}")))?;

        let inner = value
            .get("colours")
            .or_else(|| value.get("colors"))
            .unwrap_or(&value);

        let entries: Vec<&serde_json::Value> = match inner {
            serde_json::Value::Array(items) => items.iter().collect(),
            serde_json::Value::Object(map) => map
                .iter()
                // Keys beginning with an underscore are comments, which this
                // repository's json files use throughout.
                .filter(|(key, _)| !key.starts_with('_'))
                .map(|(_, v)| v)
                .collect(),
            _ => {
                return Err(Error::Spec(
                    "palette needs an array or an object of colours".into(),
                ))
            }
        };

        let mut colours = Vec::with_capacity(entries.len());
        for entry in entries {
            colours.push(parse_colour(entry)?);
        }
        Palette::new(colours)
    }

    /// The nearest palette colour, by Lab distance.
    pub fn nearest(&self, r: u8, g: u8, b: u8) -> [u8; 3] {
        let target = to_lab(r, g, b);
        let mut best = 0;
        let mut best_distance = f32::MAX;
        for (index, candidate) in self.lab.iter().enumerate() {
            let distance = lab_distance_squared(target, *candidate);
            if distance < best_distance {
                best_distance = distance;
                best = index;
            }
        }
        self.colours[best]
    }
}

/// One palette entry: a hex string, or an `[r, g, b]` or `[r, g, b, a]` array.
pub fn parse_colour(value: &serde_json::Value) -> Result<[u8; 3], Error> {
    match value {
        serde_json::Value::String(hex) => parse_hex(hex),
        serde_json::Value::Array(parts) => {
            if parts.len() < 3 {
                return Err(Error::Spec(format!(
                    "palette entry {value} needs at least three components"
                )));
            }
            let mut rgb = [0u8; 3];
            for (index, slot) in rgb.iter_mut().enumerate() {
                let raw = parts[index].as_u64().ok_or_else(|| {
                    Error::Spec(format!("palette entry {value} has a non-numeric component"))
                })?;
                if raw > 255 {
                    return Err(Error::Spec(format!(
                        "palette entry {value} has a component above 255"
                    )));
                }
                *slot = raw as u8;
            }
            Ok(rgb)
        }
        _ => Err(Error::Spec(format!(
            "palette entry {value} is neither a hex string nor an rgb array"
        ))),
    }
}

/// `#rrggbb` or `rrggbb`.
pub fn parse_hex(hex: &str) -> Result<[u8; 3], Error> {
    let trimmed = hex.trim().trim_start_matches('#');
    if trimmed.len() != 6 || !trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(Error::Spec(format!("\"{hex}\" is not a #rrggbb colour")));
    }
    let byte = |at: usize| u8::from_str_radix(&trimmed[at..at + 2], 16).unwrap_or(0);
    Ok([byte(0), byte(2), byte(4)])
}

/// The bounding box of everything not transparent, as `(x, y, w, h)`.
///
/// Returns `None` for a fully transparent image, which is a real outcome when a
/// generator returns an empty frame and is worth reporting rather than cropping
/// to nothing.
pub fn alpha_bounds(image: &RgbaImage) -> Option<(u32, u32, u32, u32)> {
    let (mut min_x, mut min_y) = (u32::MAX, u32::MAX);
    let (mut max_x, mut max_y) = (0u32, 0u32);
    let mut any = false;
    for (x, y, pixel) in image.enumerate_pixels() {
        if pixel.0[3] > TRIM_ALPHA {
            any = true;
            min_x = min_x.min(x);
            min_y = min_y.min(y);
            max_x = max_x.max(x);
            max_y = max_y.max(y);
        }
    }
    if !any {
        return None;
    }
    Some((min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))
}

/// How a sprite is reduced.
#[derive(Debug, Clone)]
pub struct Reduction {
    /// Target height in pixels. Width follows the trimmed aspect ratio.
    pub height: u32,
    /// Trim to the alpha bounding box before scaling.
    pub trim: bool,
    /// Palette to quantise to, if any.
    pub palette: Option<Palette>,
    /// Force every pixel fully opaque or fully transparent.
    pub harden_alpha: bool,
    /// Explicit flat matte colour to remove only where connected to an edge.
    pub matte: Option<[u8; 3]>,
    /// A chroma key removed everywhere, with its tolerance and fringe erosion.
    pub key: Option<ChromaKey>,
}

/// A background colour asked for in the prompt and absent from the subject.
///
/// Generators paint backgrounds rather than returning alpha, and they never
/// paint one exact colour, so the key matches by distance in L\*a\*b\*. Pixels
/// next to the key carry a blend of subject and background; `erode` removes
/// that many source pixels of fringe so the palette step cannot turn the blend
/// into an outline of the key colour.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ChromaKey {
    pub colour: [u8; 3],
    /// Largest L\*a\*b\* distance still treated as background.
    pub tolerance: f32,
    /// Source pixels of fringe removed around keyed areas.
    pub erode: u32,
}

impl Default for Reduction {
    fn default() -> Self {
        Reduction {
            height: 128,
            trim: true,
            palette: None,
            harden_alpha: true,
            matte: None,
            key: None,
        }
    }
}

/// Run the reduction.
pub fn reduce(source: &RgbaImage, settings: &Reduction) -> Result<RgbaImage, Error> {
    if settings.height == 0 {
        return Err(Error::Spec("target height must be above zero".into()));
    }

    if source.width() == 0 || source.height() == 0 {
        return Err(Error::Spec("image has no pixels".into()));
    }
    let mut working = source.clone();
    if let Some(matte) = settings.matte {
        remove_edge_matte(&mut working, matte);
    }
    if let Some(key) = settings.key {
        remove_chroma_key(&mut working, key)?;
    }
    let working = if settings.trim {
        match alpha_bounds(&working) {
            Some((x, y, w, h)) => working.view(x, y, w, h).to_image(),
            None => return Err(Error::Spec("image is entirely transparent".into())),
        }
    } else {
        working
    };

    let (sw, sh) = working.dimensions();
    // Keep the aspect ratio of what is actually drawn, and never round a
    // dimension away to nothing.
    let target_h = settings.height;
    let target_w = (((u64::from(sw) * u64::from(target_h)) as f64) / f64::from(sh)).round() as u32;
    let target_w = target_w.max(1);

    // Filter before palette reduction; nearest-neighbour is for display upscales.
    // Filter premultiplied, so the colour hidden under a removed background
    // cannot bleed into the edge of the subject.
    let mut out = unpremultiply_into(&imageops::resize(
        &premultiply(&working),
        target_w,
        target_h,
        imageops::FilterType::Triangle,
    ));

    if let Some(palette) = &settings.palette {
        for pixel in out.pixels_mut() {
            let [r, g, b, a] = pixel.0;
            // Nothing is gained by matching a colour nobody can see, and a
            // transparent pixel's colour is usually meaningless.
            if a == 0 {
                continue;
            }
            let [nr, ng, nb] = palette.nearest(r, g, b);
            *pixel = Rgba([nr, ng, nb, a]);
        }
    }

    if settings.harden_alpha {
        for pixel in out.pixels_mut() {
            pixel.0[3] = if pixel.0[3] > ALPHA_CUT { 255 } else { 0 };
        }
    }

    Ok(out)
}

/// Colour scaled by alpha in 16-bit, so filtering weights each sample by how
/// much of it is actually there.
fn premultiply(image: &RgbaImage) -> ImageBuffer<Rgba<u16>, Vec<u16>> {
    ImageBuffer::from_fn(image.width(), image.height(), |x, y| {
        let [r, g, b, a] = image.get_pixel(x, y).0;
        let scale = |c: u8| (u32::from(c) * u32::from(a) * 257 / 255) as u16;
        Rgba([scale(r), scale(g), scale(b), u16::from(a) * 257])
    })
}

/// Back from premultiplied 16-bit to straight 8-bit colour.
fn unpremultiply_into(source: &ImageBuffer<Rgba<u16>, Vec<u16>>) -> RgbaImage {
    ImageBuffer::from_fn(source.width(), source.height(), |x, y| {
        let [r, g, b, a] = source.get_pixel(x, y).0;
        if a == 0 {
            return Rgba([0, 0, 0, 0]);
        }
        let straight =
            |c: u16| ((u32::from(c) * 255 + u32::from(a) / 2) / u32::from(a)).min(255) as u8;
        Rgba([straight(r), straight(g), straight(b), (a / 257) as u8])
    })
}

/// Remove an explicitly selected exact flat matte. Flooding from every edge
/// preserves enclosed highlights of the same colour. This is preparation for
/// reviewed flat-background art, not a guess about a picture's subject.
pub fn remove_edge_matte(image: &mut RgbaImage, matte: [u8; 3]) {
    let (width, height) = image.dimensions();
    if width == 0 || height == 0 {
        return;
    }
    let mut pending = Vec::new();
    for x in 0..width {
        pending.push((x, 0));
        pending.push((x, height - 1));
    }
    for y in 0..height {
        pending.push((0, y));
        pending.push((width - 1, y));
    }
    // Mark on visit, including already transparent pixels, to bound work by
    // image size rather than the number of routes through the background.
    let mut visited = vec![false; image.pixels().len()];
    while let Some((x, y)) = pending.pop() {
        let index = y as usize * width as usize + x as usize;
        if visited[index] {
            continue;
        }
        visited[index] = true;
        let pixel = image.get_pixel_mut(x, y);
        if pixel.0[3] != 0 && pixel.0[..3] != matte {
            continue;
        }
        pixel.0[3] = 0;
        if x > 0 {
            pending.push((x - 1, y));
        }
        if x + 1 < width {
            pending.push((x + 1, y));
        }
        if y > 0 {
            pending.push((x, y - 1));
        }
        if y + 1 < height {
            pending.push((x, y + 1));
        }
    }
}

/// Remove a chroma key everywhere it appears, then erode its fringe.
///
/// Unlike the edge matte this also clears enclosed background, such as the
/// gap between a trigger guard and a grip, which is why it is reserved for a
/// key colour the prompt kept out of the subject.
pub fn remove_chroma_key(image: &mut RgbaImage, key: ChromaKey) -> Result<(), Error> {
    if !key.tolerance.is_finite() || key.tolerance <= 0.0 || key.tolerance > 100.0 {
        return Err(Error::Spec(format!(
            "key tolerance {} must be above 0 and at most 100",
            key.tolerance
        )));
    }
    if key.erode > 16 {
        return Err(Error::Spec(format!(
            "key erosion {} is more than 16 source pixels",
            key.erode
        )));
    }
    let target = to_lab(key.colour[0], key.colour[1], key.colour[2]);
    let limit = key.tolerance * key.tolerance;
    let (width, height) = image.dimensions();
    let mut cleared = vec![false; (width as usize) * (height as usize)];
    for (x, y, pixel) in image.enumerate_pixels_mut() {
        let [r, g, b, a] = pixel.0;
        if a == 0 || lab_distance_squared(to_lab(r, g, b), target) <= limit {
            pixel.0[3] = 0;
            cleared[y as usize * width as usize + x as usize] = true;
        }
    }
    for _ in 0..key.erode {
        let previous = cleared.clone();
        for y in 0..height {
            for x in 0..width {
                let index = y as usize * width as usize + x as usize;
                if previous[index] {
                    continue;
                }
                let near = (x > 0 && previous[index - 1])
                    || (x + 1 < width && previous[index + 1])
                    || (y > 0 && previous[index - width as usize])
                    || (y + 1 < height && previous[index + width as usize]);
                if near {
                    cleared[index] = true;
                    image.get_pixel_mut(x, y).0[3] = 0;
                }
            }
        }
    }
    Ok(())
}

/// Load, reduce, save.
pub fn reduce_file(input: &Path, output: &Path, settings: &Reduction) -> Result<(u32, u32), Error> {
    let image = image::open(input)
        .map_err(|e| Error::Io(format!("could not read {}: {e}", input.display())))?
        .to_rgba8();
    let reduced = reduce(&image, settings)?;
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent).map_err(|e| Error::Io(e.to_string()))?;
    }
    reduced
        .save(output)
        .map_err(|e| Error::Io(format!("could not write {}: {e}", output.display())))?;
    Ok(reduced.dimensions())
}

/// An upscale by an exact integer with no interpolation, for looking at a small
/// sprite without a viewer smoothing it into mush.
pub fn nearest_upscale(source: &RgbaImage, factor: u32) -> RgbaImage {
    let (w, h) = source.dimensions();
    let factor = factor.max(1);
    ImageBuffer::from_fn(w * factor, h * factor, |x, y| {
        *source.get_pixel(x / factor, y / factor)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(w: u32, h: u32, colour: [u8; 4]) -> RgbaImage {
        ImageBuffer::from_pixel(w, h, Rgba(colour))
    }

    #[test]
    fn edge_matte_preserves_enclosed_matching_highlights() {
        let mut image = solid(7, 7, [232, 226, 214, 255]);
        for y in 1..6 {
            for x in 1..6 {
                image.put_pixel(x, y, Rgba([40, 40, 40, 255]));
            }
        }
        image.put_pixel(3, 3, Rgba([232, 226, 214, 255]));
        remove_edge_matte(&mut image, [232, 226, 214]);
        assert_eq!(alpha_bounds(&image), Some((1, 1, 5, 5)));
        assert_eq!(image.get_pixel(3, 3).0, [232, 226, 214, 255]);
        assert_eq!(image.get_pixel(0, 0).0[3], 0);
    }

    #[test]
    fn edge_matte_reaches_disconnected_edges_and_transparent_paths() {
        let mut image = solid(5, 3, [10, 20, 30, 255]);
        for y in 0..3 {
            image.put_pixel(2, y, Rgba([1, 2, 3, 255]));
        }
        image.put_pixel(4, 0, Rgba([0, 0, 0, 0]));
        remove_edge_matte(&mut image, [10, 20, 30]);
        assert_eq!(alpha_bounds(&image), Some((2, 0, 1, 3)));
        remove_edge_matte(&mut RgbaImage::new(0, 0), [0, 0, 0]);
    }

    #[test]
    fn reduction_keys_before_trimming_and_refuses_empty_art() {
        let settings = Reduction {
            height: 3,
            matte: Some([10, 20, 30]),
            ..Reduction::default()
        };
        let mut source = solid(5, 5, [10, 20, 30, 255]);
        assert!(reduce(&source, &settings).is_err());
        source.put_pixel(2, 2, Rgba([40, 50, 60, 255]));
        let result = reduce(&source, &settings).unwrap();
        assert_eq!(result.dimensions(), (3, 3));
        assert!(result.pixels().all(|p| p.0 == [40, 50, 60, 255]));
        assert!(reduce(&RgbaImage::new(0, 0), &settings).is_err());
    }

    #[test]
    fn hex_parses_with_and_without_a_hash() {
        assert_eq!(parse_hex("#ff8000").unwrap(), [255, 128, 0]);
        assert_eq!(parse_hex("ff8000").unwrap(), [255, 128, 0]);
        assert!(parse_hex("#ff80").is_err());
        assert!(parse_hex("#gggggg").is_err());
    }

    #[test]
    fn lab_puts_black_at_zero_and_white_at_one_hundred() {
        let black = to_lab(0, 0, 0);
        let white = to_lab(255, 255, 255);
        assert!(black.l.abs() < 0.01, "{black:?}");
        assert!((white.l - 100.0).abs() < 0.01, "{white:?}");
        assert!(white.a.abs() < 0.01 && white.b.abs() < 0.01);
    }

    #[test]
    fn lab_distance_is_zero_for_a_colour_against_itself() {
        let c = to_lab(180, 90, 40);
        assert!(lab_distance_squared(c, c).abs() < 1e-6);
    }

    #[test]
    fn nearest_picks_the_obvious_swatch() {
        let palette = Palette::new(vec![[0, 0, 0], [255, 255, 255], [200, 80, 30]]).unwrap();
        assert_eq!(palette.nearest(250, 250, 250), [255, 255, 255]);
        assert_eq!(palette.nearest(5, 5, 5), [0, 0, 0]);
        assert_eq!(palette.nearest(190, 85, 35), [200, 80, 30]);
    }

    #[test]
    fn nearest_in_lab_beats_nearest_in_rgb_on_a_dark_colour() {
        // Naive RGB distance sends a very dark blue to black; Lab keeps the
        // hue, which is the failure this whole conversion exists to avoid.
        let palette = Palette::new(vec![[0, 0, 0], [40, 40, 120]]).unwrap();
        assert_eq!(palette.nearest(20, 20, 90), [40, 40, 120]);
    }

    #[test]
    fn palette_reads_a_bare_array_or_a_wrapped_one() {
        // Doubled hashes: a `"#` inside a single-hash raw string ends it.
        let bare = Palette::from_json(r##"["#000000","#ffffff"]"##).unwrap();
        assert_eq!(bare.colours.len(), 2);
        let wrapped = Palette::from_json(r##"{"colours":["#112233"]}"##).unwrap();
        assert_eq!(wrapped.colours, vec![[0x11, 0x22, 0x33]]);
        let american = Palette::from_json(r##"{"colors":["#112233"]}"##).unwrap();
        assert_eq!(american.colours.len(), 1);
    }

    #[test]
    fn palette_reads_the_repositorys_own_named_rgba_format() {
        // This is the shape docs/palette.json was already in. The tool adapts
        // to the project rather than the project to the tool.
        let palette = Palette::from_json(
            r#"{
              "_comment": "ignored",
              "ink": [10, 10, 12, 255],
              "bone": [232, 226, 214, 255],
              "rust": [122, 58, 34, 255]
            }"#,
        )
        .unwrap();
        assert_eq!(palette.colours.len(), 3, "the comment key is not a colour");
        assert!(palette.colours.contains(&[10, 10, 12]));
        assert!(palette.colours.contains(&[232, 226, 214]));
        assert_eq!(palette.nearest(12, 12, 14), [10, 10, 12]);
    }

    #[test]
    fn palette_accepts_rgb_without_an_alpha() {
        let palette = Palette::from_json(r#"{"ink": [10, 10, 12]}"#).unwrap();
        assert_eq!(palette.colours, vec![[10, 10, 12]]);
    }

    #[test]
    fn a_malformed_colour_is_refused_rather_than_guessed() {
        assert!(Palette::from_json(r#"{"ink": [10, 10]}"#).is_err());
        assert!(Palette::from_json(r#"{"ink": [10, 10, 999]}"#).is_err());
        assert!(Palette::from_json(r#"{"ink": ["a", "b", "c"]}"#).is_err());
        assert!(Palette::from_json(r#"{"ink": 5}"#).is_err());
    }

    #[test]
    fn the_real_project_palette_loads() {
        let text = std::fs::read_to_string(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/palette.json"),
        )
        .expect("docs/palette.json should exist");
        let palette = Palette::from_json(&text).expect("the project palette should parse");
        assert!(
            palette.colours.len() >= 8,
            "expected a real palette, got {}",
            palette.colours.len()
        );
    }

    #[test]
    fn an_empty_palette_is_refused() {
        assert!(Palette::new(Vec::new()).is_err());
        assert!(Palette::from_json("[]").is_err());
    }

    #[test]
    fn alpha_bounds_finds_the_drawn_region() {
        let mut image = solid(10, 10, [0, 0, 0, 0]);
        image.put_pixel(3, 4, Rgba([255, 0, 0, 255]));
        image.put_pixel(6, 8, Rgba([255, 0, 0, 255]));
        assert_eq!(alpha_bounds(&image), Some((3, 4, 4, 5)));
    }

    #[test]
    fn a_fully_transparent_image_has_no_bounds() {
        assert_eq!(alpha_bounds(&solid(4, 4, [9, 9, 9, 0])), None);
    }

    #[test]
    fn reduce_hits_the_target_height_and_keeps_the_aspect_ratio() {
        let source = solid(400, 200, [10, 20, 30, 255]);
        let out = reduce(
            &source,
            &Reduction {
                height: 64,
                trim: false,
                ..Reduction::default()
            },
        )
        .unwrap();
        assert_eq!(out.dimensions(), (128, 64));
    }

    #[test]
    fn reduce_measures_the_ratio_after_trimming_not_before() {
        // A tall canvas holding a wide sprite. Without trimming first the
        // output would be shaped like the canvas instead of like the sprite.
        let mut source = solid(200, 400, [0, 0, 0, 0]);
        for x in 0..100 {
            for y in 0..50 {
                source.put_pixel(x, y + 100, Rgba([200, 80, 30, 255]));
            }
        }
        let out = reduce(
            &source,
            &Reduction {
                height: 50,
                trim: true,
                palette: None,
                harden_alpha: true,
                matte: None,
                key: None,
            },
        )
        .unwrap();
        assert_eq!(out.dimensions(), (100, 50));
    }

    #[test]
    fn reduce_refuses_an_empty_image_rather_than_producing_nothing() {
        let err = reduce(&solid(8, 8, [0, 0, 0, 0]), &Reduction::default()).unwrap_err();
        assert!(format!("{err}").contains("transparent"), "{err}");
    }

    #[test]
    fn reduce_refuses_a_zero_height() {
        let settings = Reduction {
            height: 0,
            ..Reduction::default()
        };
        assert!(reduce(&solid(8, 8, [1, 2, 3, 255]), &settings).is_err());
    }

    #[test]
    fn quantisation_leaves_only_palette_colours_behind() {
        let mut source = solid(64, 64, [0, 0, 0, 255]);
        for (i, pixel) in source.pixels_mut().enumerate() {
            let v = (i % 256) as u8;
            *pixel = Rgba([v, v / 2, 255 - v, 255]);
        }
        let palette = Palette::new(vec![[0, 0, 0], [255, 255, 255], [200, 80, 30]]).unwrap();
        let out = reduce(
            &source,
            &Reduction {
                height: 16,
                trim: false,
                palette: Some(palette.clone()),
                harden_alpha: true,
                matte: None,
                key: None,
            },
        )
        .unwrap();
        for pixel in out.pixels() {
            let rgb = [pixel.0[0], pixel.0[1], pixel.0[2]];
            assert!(palette.colours.contains(&rgb), "stray colour {rgb:?}");
        }
    }

    #[test]
    fn hardening_leaves_no_half_transparent_edge() {
        let mut source = solid(32, 32, [200, 80, 30, 255]);
        source.put_pixel(0, 0, Rgba([200, 80, 30, 100]));
        source.put_pixel(1, 1, Rgba([200, 80, 30, 200]));
        let out = reduce(
            &source,
            &Reduction {
                height: 32,
                trim: false,
                palette: None,
                harden_alpha: true,
                matte: None,
                key: None,
            },
        )
        .unwrap();
        assert!(out.pixels().all(|p| p.0[3] == 0 || p.0[3] == 255));
    }

    #[test]
    fn hardening_can_be_turned_off() {
        let mut source = solid(8, 8, [200, 80, 30, 255]);
        source.put_pixel(4, 4, Rgba([200, 80, 30, 100]));
        let out = reduce(
            &source,
            &Reduction {
                height: 8,
                trim: false,
                palette: None,
                harden_alpha: false,
                matte: None,
                key: None,
            },
        )
        .unwrap();
        assert!(out.pixels().any(|p| p.0[3] != 0 && p.0[3] != 255));
    }

    #[test]
    fn nearest_upscale_repeats_pixels_exactly() {
        let mut source = solid(2, 2, [0, 0, 0, 255]);
        source.put_pixel(0, 0, Rgba([255, 0, 0, 255]));
        let out = nearest_upscale(&source, 4);
        assert_eq!(out.dimensions(), (8, 8));
        for y in 0..4 {
            for x in 0..4 {
                assert_eq!(out.get_pixel(x, y).0, [255, 0, 0, 255]);
            }
        }
        assert_eq!(out.get_pixel(5, 5).0, [0, 0, 0, 255]);
    }

    #[test]
    fn a_transparent_pixel_keeps_its_alpha_through_quantisation() {
        let mut source = solid(16, 16, [200, 80, 30, 255]);
        for x in 0..16 {
            source.put_pixel(x, 0, Rgba([0, 0, 0, 0]));
        }
        let palette = Palette::new(vec![[255, 255, 255]]).unwrap();
        let out = reduce(
            &source,
            &Reduction {
                height: 16,
                trim: false,
                palette: Some(palette),
                harden_alpha: true,
                matte: None,
                key: None,
            },
        )
        .unwrap();
        assert!(out.pixels().any(|p| p.0[3] == 0), "transparency survived");
    }
}

#[cfg(test)]
mod key_tests {
    use super::*;

    const MAGENTA: [u8; 3] = [255, 0, 255];

    fn keyed(tolerance: f32, erode: u32) -> ChromaKey {
        ChromaKey {
            colour: MAGENTA,
            tolerance,
            erode,
        }
    }

    #[test]
    fn a_painted_key_clears_enclosed_and_near_colours_but_not_the_subject() {
        // A noisy magenta field, a grey subject, and an enclosed gap.
        let mut image = ImageBuffer::from_pixel(9, 9, Rgba([250, 8, 246, 255]));
        for y in 2..7 {
            for x in 2..7 {
                image.put_pixel(x, y, Rgba([90, 85, 79, 255]));
            }
        }
        image.put_pixel(4, 4, Rgba([255, 0, 255, 255]));
        image.put_pixel(0, 8, Rgba([138, 58, 88, 255]));
        remove_chroma_key(&mut image, keyed(30.0, 0)).unwrap();
        assert_eq!(image.get_pixel(0, 0).0[3], 0);
        assert_eq!(image.get_pixel(4, 4).0[3], 0, "enclosed key is cleared");
        assert_eq!(image.get_pixel(3, 3).0, [90, 85, 79, 255]);
        assert_eq!(image.get_pixel(0, 8).0[3], 255, "muted magenta survives");
    }

    #[test]
    fn erosion_strips_the_fringe_one_pixel_per_pass() {
        let mut image = ImageBuffer::from_pixel(7, 7, Rgba([255, 0, 255, 255]));
        for y in 1..6 {
            for x in 1..6 {
                image.put_pixel(x, y, Rgba([40, 40, 40, 255]));
            }
        }
        remove_chroma_key(&mut image, keyed(10.0, 1)).unwrap();
        assert_eq!(alpha_bounds(&image), Some((2, 2, 3, 3)));
        remove_chroma_key(&mut image, keyed(10.0, 1)).unwrap();
        assert_eq!(alpha_bounds(&image), Some((3, 3, 1, 1)));
    }

    #[test]
    fn reduction_applies_the_key_before_trimming() {
        let mut source = ImageBuffer::from_pixel(8, 8, Rgba([255, 0, 255, 255]));
        for y in 2..6 {
            for x in 2..6 {
                source.put_pixel(x, y, Rgba([200, 80, 30, 255]));
            }
        }
        let out = reduce(
            &source,
            &Reduction {
                height: 4,
                key: Some(keyed(20.0, 0)),
                ..Reduction::default()
            },
        )
        .unwrap();
        assert_eq!(out.dimensions(), (4, 4));
        assert!(out.pixels().all(|p| p.0 == [200, 80, 30, 255]));
    }

    #[test]
    fn unreasonable_key_settings_are_refused() {
        let mut image = RgbaImage::new(2, 2);
        for bad in [
            keyed(0.0, 0),
            keyed(f32::NAN, 0),
            keyed(101.0, 0),
            keyed(10.0, 17),
        ] {
            assert!(remove_chroma_key(&mut image, bad).is_err());
        }
    }
}

#[cfg(test)]
mod premultiplied_tests {
    use super::*;

    #[test]
    fn hidden_background_colour_does_not_bleed_into_edges() {
        // Left half: opaque grey subject. Right half: removed magenta key.
        let mut source = ImageBuffer::from_pixel(8, 8, Rgba([255, 0, 255, 0]));
        for y in 0..8 {
            for x in 0..4 {
                source.put_pixel(x, y, Rgba([90, 90, 90, 255]));
            }
        }
        let out = reduce(
            &source,
            &Reduction {
                height: 3,
                trim: false,
                harden_alpha: false,
                ..Reduction::default()
            },
        )
        .unwrap();
        for pixel in out.pixels().filter(|p| p.0[3] > 0) {
            let [r, g, b, _] = pixel.0;
            assert!(
                r.abs_diff(90) <= 1 && g.abs_diff(90) <= 1 && b.abs_diff(90) <= 1,
                "{pixel:?}"
            );
        }
    }

    #[test]
    fn premultiplying_round_trips_opaque_and_clears_empty_pixels() {
        let mut image = RgbaImage::new(2, 1);
        image.put_pixel(0, 0, Rgba([12, 200, 255, 255]));
        image.put_pixel(1, 0, Rgba([255, 0, 255, 0]));
        let back = unpremultiply_into(&premultiply(&image));
        assert_eq!(back.get_pixel(0, 0).0, [12, 200, 255, 255]);
        assert_eq!(back.get_pixel(1, 0).0, [0, 0, 0, 0]);
    }
}
