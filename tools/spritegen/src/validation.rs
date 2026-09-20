//! Validate local artifact names and remote destinations before effects occur.

use reqwest::Url;

use crate::Error;

pub fn validate_model_path(model: &str) -> Result<(), Error> {
    if model.len() > 200
        || model.split('/').any(|part| {
            part.is_empty()
                || part == "."
                || part == ".."
                || !part
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'.'))
        })
    {
        return Err(Error::Spec(
            "model must be an API catalog path without query or traversal segments".into(),
        ));
    }
    Ok(())
}

pub fn validate_api_url(raw: &str) -> Result<Url, Error> {
    let url = validate_download_url(raw)?;
    if url.host_str() != Some("api.higgsfield.ai") || url.port_or_known_default() != Some(443) {
        return Err(Error::Transport(
            "authenticated request is outside the official API origin".into(),
        ));
    }
    Ok(url)
}

pub(crate) fn validate_request_id(id: &str) -> Result<(), Error> {
    if id.is_empty()
        || id.len() > 128
        || !id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_'))
    {
        return Err(Error::Transport("invalid API request ID".into()));
    }
    Ok(())
}

pub fn validate_status_url(raw: &str) -> Result<Url, Error> {
    let url = validate_api_url(raw)?;
    let parts: Vec<&str> = url.path().split('/').collect();
    if parts.len() != 4
        || !parts[0].is_empty()
        || parts[1] != "requests"
        || parts[3] != "status"
        || validate_request_id(parts[2]).is_err()
        || url.query().is_some()
    {
        return Err(Error::Transport("invalid API request-status path".into()));
    }
    Ok(url)
}

pub(crate) fn status_request_id(raw: &str) -> Result<String, Error> {
    let url = validate_status_url(raw)?;
    // The validated path is exactly /requests/<id>/status.
    Ok(url.path().split('/').nth(2).unwrap_or_default().to_owned())
}

pub fn validate_download_url(raw: &str) -> Result<Url, Error> {
    let url = Url::parse(raw).map_err(|_| Error::Transport("invalid media/API URL".into()))?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(Error::Transport(
            "media/API URL requires HTTPS without userinfo or fragment".into(),
        ));
    }
    Ok(url)
}

pub fn validate_frame_id(id: &str) -> Result<(), Error> {
    if id.len() > 96 {
        return Err(Error::Spec("frame ID exceeds 96 bytes".into()));
    }
    validate_file_name(id)
}

pub(crate) fn validate_file_name(name: &str) -> Result<(), Error> {
    let base = name.split('.').next().unwrap_or("").to_ascii_uppercase();
    let device = matches!(base.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || ((base.starts_with("COM") || base.starts_with("LPT"))
            && base.len() == 4
            && matches!(base.as_bytes()[3], b'1'..=b'9'));
    if name.is_empty()
        || name.len() > 128
        || name.starts_with('.')
        || name.ends_with('.')
        || name.contains("..")
        || device
        || !name
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'.'))
    {
        return Err(Error::Spec(
            "asset name must be a portable filename using letters, numbers, _, - and .".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn credentials_are_bound_to_the_official_https_origin() {
        assert!(validate_api_url("https://api.higgsfield.ai:443/estimate/m").is_ok());
        for url in [
            "http://api.higgsfield.ai/m",
            "https://api.higgsfield.ai.evil/m",
            "https://api.higgsfield.ai@evil/m",
            "https://evil@api.higgsfield.ai/m",
            "https://api.higgsfield.ai:444/m",
            "https://api.higgsfield.ai/m#fragment",
            "broken",
        ] {
            assert!(validate_api_url(url).is_err(), "{url}");
        }
    }

    #[test]
    fn model_names_cannot_escape_the_free_estimate_route() {
        assert!(validate_model_path("marketing-studio/image").is_ok());
        assert!(validate_model_path("ideogram/v4.0").is_ok());
        for bad in [
            "",
            "../marketing-studio/image",
            "x/../y",
            "x//y",
            "/x",
            "x?key=y",
            "x#y",
            "%2e%2e/x",
            "x\\y",
        ] {
            assert!(validate_model_path(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn status_paths_cannot_be_other_authenticated_operations() {
        assert!(validate_status_url("https://api.higgsfield.ai/requests/a-1/status").is_ok());
        for path in [
            "/requests/x/cancel",
            "/requests//status",
            "/requests/a/b/status",
            "/requests/x/status?q=1",
            "/requests/x%2Fy/status",
            "/billing",
        ] {
            assert!(validate_status_url(&format!("https://api.higgsfield.ai{path}")).is_err());
        }
    }

    #[test]
    fn artifact_names_are_portable_and_stay_within_the_output() {
        for good in ["tack_issued", "NODS-front.01", "comrade", "a"] {
            assert!(validate_frame_id(good).is_ok());
        }
        for bad in [
            "", "../x", "x/y", "x\\y", "x:y", ".env", "x.", "x ", "CON", "aux.png", "lpt9", "a\n",
        ] {
            assert!(validate_frame_id(bad).is_err(), "{bad}");
        }
        assert!(validate_frame_id(&"a".repeat(97)).is_err());
        assert!(validate_file_name(&format!("{}_0.png", "a".repeat(96))).is_ok());
    }
}
