//! Reference images for consistency.
//!
//! A set holds together when one approved picture is handed back to the model
//! as a reference for the rest. The provider takes references as URLs, so a
//! local keeper is first uploaded: `POST /files/generate-upload-url` returns a
//! presigned storage URL and a public URL, and the bytes go to the storage URL
//! with the headers it names. Uploading is free; the request that later uses
//! the public URL is priced and capped like any other.
//!
//! The credential goes only to the API origin. The presigned storage URL
//! carries its own authority, so it never receives the `Authorization` header,
//! and the tool sends exactly the headers the API returned and nothing else.

use serde_json::Value;

use crate::{validation, Error, Method, Request, Transport, API_BASE};

/// Largest reference the tool will send. Generated keepers are a few MB.
pub const MAX_REFERENCE_BYTES: usize = 24 * 1024 * 1024;

/// A reference that the provider now holds.
#[derive(Debug, Clone, PartialEq)]
pub struct Uploaded {
    /// The URL a request passes in `image_urls`.
    pub public_url: String,
    pub content_type: String,
    pub bytes: usize,
}

/// The content type the API accepts for an image file name.
pub fn content_type_for(name: &str) -> Result<&'static str, Error> {
    let extension = name
        .rsplit('.')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase();
    match extension.as_str() {
        "png" => Ok("image/png"),
        "jpg" | "jpeg" => Ok("image/jpeg"),
        "webp" => Ok("image/webp"),
        _ => Err(Error::Spec(format!(
            "\"{name}\" is not a png, jpeg or webp reference image"
        ))),
    }
}

/// Header names the presigned upload may ask for. Anything else is refused
/// rather than forwarded, because the storage host is not the API.
fn allowed_upload_header(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower == "content-type" || (lower.starts_with("x-amz-") && lower.len() <= 64)
}

fn header_value_is_plain(value: &str) -> bool {
    !value.is_empty() && value.len() <= 512 && value.bytes().all(|b| (0x20..0x7f).contains(&b))
}

/// Upload one image and return the URL a generation request can reference.
pub fn upload_reference(
    transport: &dyn Transport,
    credential: &str,
    content_type: &str,
    body: Vec<u8>,
) -> Result<Uploaded, Error> {
    if body.is_empty() || body.len() > MAX_REFERENCE_BYTES {
        return Err(Error::Spec(format!(
            "reference must be between 1 byte and {MAX_REFERENCE_BYTES} bytes, got {}",
            body.len()
        )));
    }
    let request = Request {
        method: Method::Post,
        url: format!("{API_BASE}/files/generate-upload-url"),
        body: Some(serde_json::json!({ "content_type": content_type }).to_string()),
    };
    let response = transport.send(credential, &request)?;
    if response.status != 200 && response.status != 201 {
        return Err(Error::Api {
            status: response.status,
            body: response.body,
        });
    }
    let value: Value = serde_json::from_str(&response.body)
        .map_err(|e| Error::Transport(format!("upload URL reply was not json: {e}")))?;
    let field = |name: &str| -> Result<String, Error> {
        value
            .get(name)
            .and_then(Value::as_str)
            .map(str::to_string)
            .ok_or_else(|| Error::Transport(format!("upload URL reply had no \"{name}\"")))
    };
    let public_url = field("public_url")?;
    let upload_url = field("upload_url")?;
    validation::validate_download_url(&public_url)?;
    let upload = validation::validate_download_url(&upload_url)?;
    if upload.host_str() == Some("api.higgsfield.ai") {
        return Err(Error::Transport(
            "presigned upload must not target the authenticated API origin".into(),
        ));
    }
    if let Some(returned) = value.get("content_type").and_then(Value::as_str) {
        if returned != content_type {
            return Err(Error::Transport(format!(
                "upload URL was issued for {returned}, not {content_type}"
            )));
        }
    }

    let mut headers: Vec<(String, String)> = Vec::new();
    if let Some(map) = value.get("upload_headers").and_then(Value::as_object) {
        for (name, raw) in map {
            let text = raw
                .as_str()
                .ok_or_else(|| Error::Transport(format!("upload header {name} is not a string")))?;
            if !allowed_upload_header(name) || !header_value_is_plain(text) {
                return Err(Error::Transport(format!(
                    "upload header {name} is not one the tool forwards"
                )));
            }
            headers.push((name.clone(), text.to_string()));
        }
    }
    match headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("content-type"))
    {
        Some((_, value)) if value != content_type => {
            return Err(Error::Transport(format!(
                "upload headers name {value}, not {content_type}"
            )));
        }
        Some(_) => {}
        None => headers.push(("Content-Type".into(), content_type.into())),
    }

    let bytes = body.len();
    let status = transport.put(&upload_url, &headers, body)?;
    if !(200..300).contains(&status) {
        return Err(Error::Api {
            status,
            body: "uploading the reference to its presigned URL".into(),
        });
    }
    Ok(Uploaded {
        public_url,
        content_type: content_type.into(),
        bytes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Response;
    use std::cell::RefCell;

    /// One recorded upload: URL, headers and body length.
    type Put = (String, Vec<(String, String)>, usize);

    struct Storage {
        reply: Response,
        put_status: u16,
        sent: RefCell<Vec<Request>>,
        puts: RefCell<Vec<Put>>,
    }

    impl Storage {
        fn new(body: &str, put_status: u16) -> Self {
            Storage {
                reply: Response {
                    status: 200,
                    body: body.into(),
                },
                put_status,
                sent: RefCell::new(Vec::new()),
                puts: RefCell::new(Vec::new()),
            }
        }
    }

    impl Transport for Storage {
        fn send(&self, _credential: &str, request: &Request) -> Result<Response, Error> {
            self.sent.borrow_mut().push(request.clone());
            Ok(self.reply.clone())
        }

        fn download(&self, _url: &str) -> Result<Vec<u8>, Error> {
            Err(Error::Transport("not used".into()))
        }

        fn put(
            &self,
            url: &str,
            headers: &[(String, String)],
            body: Vec<u8>,
        ) -> Result<u16, Error> {
            self.puts
                .borrow_mut()
                .push((url.into(), headers.to_vec(), body.len()));
            Ok(self.put_status)
        }
    }

    const GOOD: &str = r#"{"public_url":"https://cdn.example.com/input/a.png",
        "upload_url":"https://storage.example.com/presigned?sig=1",
        "content_type":"image/png",
        "upload_headers":{"Content-Type":"image/png","x-amz-tagging":"retention=temporary"}}"#;

    #[test]
    fn upload_asks_the_api_then_puts_only_the_named_headers() {
        let storage = Storage::new(GOOD, 200);
        let uploaded = upload_reference(&storage, "id:secret", "image/png", vec![7; 10]).unwrap();
        assert_eq!(uploaded.public_url, "https://cdn.example.com/input/a.png");
        assert_eq!(uploaded.bytes, 10);
        let sent = storage.sent.borrow();
        assert_eq!(sent.len(), 1);
        assert_eq!(
            sent[0].url,
            "https://api.higgsfield.ai/files/generate-upload-url"
        );
        assert!(sent[0].body.as_deref().unwrap().contains("image/png"));
        let puts = storage.puts.borrow();
        assert_eq!(puts.len(), 1);
        assert_eq!(puts[0].0, "https://storage.example.com/presigned?sig=1");
        assert_eq!(puts[0].1.len(), 2);
        assert!(puts[0]
            .1
            .iter()
            .all(|(name, _)| !name.eq_ignore_ascii_case("authorization")));
    }

    #[test]
    fn a_missing_content_type_header_is_supplied() {
        let storage = Storage::new(
            r#"{"public_url":"https://cdn.example.com/a.png","upload_url":"https://s.example.com/p"}"#,
            204,
        );
        upload_reference(&storage, "k", "image/png", vec![1]).unwrap();
        let puts = storage.puts.borrow();
        assert_eq!(puts[0].1, vec![("Content-Type".into(), "image/png".into())]);
    }

    #[test]
    fn unsafe_or_mismatched_replies_are_refused_before_any_upload() {
        for body in [
            r#"{"public_url":"http://cdn.example.com/a.png","upload_url":"https://s.example.com/p"}"#,
            r#"{"public_url":"https://cdn.example.com/a.png","upload_url":"https://api.higgsfield.ai/p"}"#,
            r#"{"public_url":"https://cdn.example.com/a.png","upload_url":"https://s.example.com/p","content_type":"image/jpeg"}"#,
            r#"{"public_url":"https://cdn.example.com/a.png","upload_url":"https://s.example.com/p","upload_headers":{"Authorization":"x"}}"#,
            r#"{"public_url":"https://cdn.example.com/a.png","upload_url":"https://s.example.com/p","upload_headers":{"Content-Type":"image/jpeg"}}"#,
            r#"{"public_url":"https://cdn.example.com/a.png","upload_url":"https://s.example.com/p","upload_headers":{"x-amz-tagging":7}}"#,
            r#"{"upload_url":"https://s.example.com/p"}"#,
            "not json",
        ] {
            let storage = Storage::new(body, 200);
            assert!(
                upload_reference(&storage, "k", "image/png", vec![1]).is_err(),
                "{body}"
            );
            assert!(storage.puts.borrow().is_empty(), "{body}");
        }
    }

    #[test]
    fn failed_storage_and_api_errors_and_bad_sizes_are_errors() {
        let storage = Storage::new(GOOD, 403);
        assert!(matches!(
            upload_reference(&storage, "k", "image/png", vec![1]),
            Err(Error::Api { status: 403, .. })
        ));
        let mut refused = Storage::new("{}", 200);
        refused.reply.status = 401;
        assert!(matches!(
            upload_reference(&refused, "k", "image/png", vec![1]),
            Err(Error::Api { status: 401, .. })
        ));
        assert!(upload_reference(&storage, "k", "image/png", Vec::new()).is_err());
        assert!(
            upload_reference(&storage, "k", "image/png", vec![0; MAX_REFERENCE_BYTES + 1]).is_err()
        );
    }

    #[test]
    fn content_types_follow_the_extension() {
        assert_eq!(content_type_for("a.PNG").unwrap(), "image/png");
        assert_eq!(content_type_for("b.jpeg").unwrap(), "image/jpeg");
        assert_eq!(content_type_for("c.webp").unwrap(), "image/webp");
        assert!(content_type_for("d.gif").is_err());
        assert!(content_type_for("noextension").is_err());
    }
}
