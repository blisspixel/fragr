//! Writes the wire MapInfo of an authored map file for offline presentation
//! review (`tools/preview_campaign_props.gd`). Run with `--ignored`; both
//! paths are absolute because cargo runs the test from `server/`:
//!   LOCALEXCEPTION_MAP_FILE=/abs/server/maps/m19-planned-works.json LOCALEXCEPTION_MAP_INFO=/abs/out.json \
//!     cargo test -p localexception-server --lib authored_write_map_info -- --ignored

#[test]
#[ignore = "writes the MapInfo used by the offline campaign prop preview"]
fn authored_write_map_info() {
    let (Ok(source), Ok(out)) = (
        std::env::var("LOCALEXCEPTION_MAP_FILE"),
        std::env::var("LOCALEXCEPTION_MAP_INFO"),
    ) else {
        return;
    };
    let map = crate::maps::AuthoredMap::load(std::path::Path::new(&source)).expect("load map");
    let state = crate::sim::GameState::with_authored_map(map);
    let message = serde_json::to_string(&state.map_info()).expect("serialize MapInfo");
    std::fs::write(out, message).expect("write MapInfo");
}
