//! Export the production island contract for offline renderer measurements.
use fragr_server::sim::{GameState, MapKind};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("output path required")?;
    let state = GameState::with_map(MapKind::HoldfastAtoll, false);
    std::fs::write(path, serde_json::to_vec(&state.map_info())?)?;
    Ok(())
}
