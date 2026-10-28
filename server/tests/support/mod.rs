//! A test client connection that holds the world it last read, so snapshot
//! deltas (gameplay 61) read as whole worlds through `WorldReader`.

use fragr_server::protocol::{delta::ReadError, ServerMessage, WorldReader};
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Stream = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;

pub struct Socket {
    ws: Stream,
    frames: WorldReader,
}

impl std::ops::Deref for Socket {
    type Target = Stream;
    fn deref(&self) -> &Stream {
        &self.ws
    }
}

impl std::ops::DerefMut for Socket {
    fn deref_mut(&mut self) -> &mut Stream {
        &mut self.ws
    }
}

// Each test crate includes this module and uses only part of it.
#[allow(dead_code)]
impl Socket {
    /// One text frame as a message; a delta becomes the whole world.
    pub fn read(&mut self, text: &str) -> Result<ServerMessage, ReadError> {
        self.frames.read(text)
    }

    /// One text frame as JSON; a delta becomes the whole world's value.
    pub fn read_value(&mut self, text: &str) -> Result<serde_json::Value, ReadError> {
        self.frames.read_value(text)
    }
}

/// `tokio_tungstenite::connect_async`, with a fresh world reader.
pub async fn connect_async(
    url: &str,
) -> Result<
    (
        Socket,
        tokio_tungstenite::tungstenite::handshake::client::Response,
    ),
    Box<tokio_tungstenite::tungstenite::Error>,
> {
    let (ws, response) = tokio_tungstenite::connect_async(url)
        .await
        .map_err(Box::new)?;
    Ok((
        Socket {
            ws,
            frames: WorldReader::new(),
        },
        response,
    ))
}
