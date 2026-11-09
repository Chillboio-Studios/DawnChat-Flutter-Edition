use once_cell::sync::Lazy;
use reqwest::{Client, Method};
use std::str::FromStr;
use std::time::Duration;

static CLIENT: Lazy<Client> = Lazy::new(|| {
    Client::builder()
        .user_agent("DawnChat-Flutter")
        .connect_timeout(Duration::from_secs(15))
        .build()
        .expect("failed to build HTTP client")
});

pub struct HttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
    pub content_type: Option<String>,
}

fn apply_headers(
    mut req: reqwest::RequestBuilder,
    headers: Vec<(String, String)>,
) -> reqwest::RequestBuilder {
    for (k, v) in headers {
        req = req.header(k, v);
    }
    req
}

async fn finish(req: reqwest::RequestBuilder) -> anyhow::Result<HttpResponse> {
    let res = req.send().await?;
    let status = res.status().as_u16();
    let content_type = res
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);
    let body = res.bytes().await?.to_vec();
    Ok(HttpResponse {
        status,
        body,
        content_type,
    })
}

/// Performs an HTTP request and returns the raw response.
pub async fn http_request(
    method: String,
    url: String,
    headers: Vec<(String, String)>,
    body: Option<Vec<u8>>,
) -> anyhow::Result<HttpResponse> {
    let method = Method::from_str(&method.to_uppercase())?;
    let mut req = CLIENT.request(method, url).timeout(Duration::from_secs(60));
    req = apply_headers(req, headers);
    if let Some(body) = body {
        req = req.body(body);
    }
    finish(req).await
}

/// Uploads a single file as multipart/form-data (Autumn file server).
pub async fn http_upload(
    url: String,
    headers: Vec<(String, String)>,
    field: String,
    file_name: String,
    mime: String,
    bytes: Vec<u8>,
) -> anyhow::Result<HttpResponse> {
    let part = reqwest::multipart::Part::bytes(bytes)
        .file_name(file_name)
        .mime_str(&mime)?;
    let form = reqwest::multipart::Form::new().part(field, part);
    let req = CLIENT
        .post(url)
        .timeout(Duration::from_secs(60 * 30))
        .multipart(form);
    finish(apply_headers(req, headers)).await
}
