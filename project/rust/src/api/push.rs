//! Web Push (RFC 8030/8291) user agent for desktop platforms that have no native push service.
//! Talks to the Mozilla autopush websocket, so notifications arrive while the app is running
//! in the background or the tray, using the same `/push/subscribe` flow as the web client.

use crate::frb_generated::StreamSink;
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes128Gcm, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64;
use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use hkdf::Hkdf;
use once_cell::sync::Lazy;
use p256::{elliptic_curve::sec1::ToEncodedPoint, PublicKey, SecretKey};
use rand::RngCore;
use serde_json::{json, Value};
use sha2::Sha256;
use std::sync::Mutex;
use std::time::Duration;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio_tungstenite::tungstenite::Message;

const AUTOPUSH_URL: &str = "wss://push.services.mozilla.com/";

#[derive(Clone)]
pub struct PushSubscription {
    pub endpoint: String,
    pub p256dh: String,
    pub auth: String,
    pub private_key: String,
    pub uaid: String,
    pub channel_id: String,
}

pub enum PushEvent {
    Registered(PushSubscription),
    Notification(String),
    Closed(String),
}

static STOP: Lazy<Mutex<Option<UnboundedSender<()>>>> = Lazy::new(|| Mutex::new(None));

fn new_channel_id() -> String {
    let mut b = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let h: Vec<String> = b.iter().map(|x| format!("{x:02x}")).collect();
    format!(
        "{}-{}-{}-{}-{}",
        h[0..4].concat(),
        h[4..6].concat(),
        h[6..8].concat(),
        h[8..10].concat(),
        h[10..16].concat()
    )
}

fn decrypt(sub: &PushSubscription, payload: &[u8]) -> anyhow::Result<Vec<u8>> {
    anyhow::ensure!(payload.len() > 21, "payload too short");
    let salt = &payload[0..16];
    let id_len = payload[20] as usize;
    anyhow::ensure!(payload.len() > 21 + id_len, "payload truncated");
    let as_public_bytes = &payload[21..21 + id_len];
    let ciphertext = &payload[21 + id_len..];

    let secret = SecretKey::from_slice(&B64.decode(&sub.private_key)?)?;
    let ua_public = secret.public_key().to_encoded_point(false);
    let as_public = PublicKey::from_sec1_bytes(as_public_bytes)?;
    let shared = p256::ecdh::diffie_hellman(secret.to_nonzero_scalar(), as_public.as_affine());
    let auth = B64.decode(&sub.auth)?;

    let mut info = b"WebPush: info\0".to_vec();
    info.extend_from_slice(ua_public.as_bytes());
    info.extend_from_slice(as_public_bytes);
    let mut ikm = [0u8; 32];
    Hkdf::<Sha256>::new(Some(&auth), shared.raw_secret_bytes())
        .expand(&info, &mut ikm)
        .map_err(|e| anyhow::anyhow!("hkdf: {e}"))?;

    let hk = Hkdf::<Sha256>::new(Some(salt), &ikm);
    let mut cek = [0u8; 16];
    let mut nonce = [0u8; 12];
    hk.expand(b"Content-Encoding: aes128gcm\0", &mut cek)
        .map_err(|e| anyhow::anyhow!("hkdf: {e}"))?;
    hk.expand(b"Content-Encoding: nonce\0", &mut nonce)
        .map_err(|e| anyhow::anyhow!("hkdf: {e}"))?;

    let cipher = Aes128Gcm::new_from_slice(&cek)?;
    let mut plain = cipher
        .decrypt(Nonce::from_slice(&nonce), ciphertext)
        .map_err(|e| anyhow::anyhow!("decrypt: {e}"))?;
    while let Some(&last) = plain.last() {
        plain.pop();
        if last == 0x02 || last == 0x01 {
            break;
        }
    }
    Ok(plain)
}

fn fresh_subscription() -> PushSubscription {
    let secret = SecretKey::random(&mut rand::rngs::OsRng);
    let public = secret.public_key().to_encoded_point(false);
    let mut auth = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut auth);
    PushSubscription {
        endpoint: String::new(),
        p256dh: B64.encode(public.as_bytes()),
        auth: B64.encode(auth),
        private_key: B64.encode(secret.to_bytes()),
        uaid: String::new(),
        channel_id: new_channel_id(),
    }
}

async fn session(
    vapid_key: &str,
    sub: &mut PushSubscription,
    sink: &StreamSink<PushEvent>,
    stop: &mut tokio::sync::mpsc::UnboundedReceiver<()>,
) -> anyhow::Result<bool> {
    let (stream, _) = tokio_tungstenite::connect_async(AUTOPUSH_URL).await?;
    let (mut write, mut read) = stream.split();

    let mut hello = json!({"messageType": "hello", "use_webpush": true, "channelIDs": []});
    if !sub.uaid.is_empty() {
        hello["uaid"] = json!(sub.uaid);
        hello["channelIDs"] = json!([sub.channel_id]);
    }
    write.send(Message::Text(hello.to_string())).await?;

    let mut keepalive = tokio::time::interval(Duration::from_secs(45));
    keepalive.tick().await;

    loop {
        tokio::select! {
            _ = stop.recv() => {
                let _ = write.close().await;
                return Ok(true);
            }
            _ = keepalive.tick() => {
                write.send(Message::Text("{}".into())).await?;
            }
            msg = read.next() => {
                let Some(msg) = msg else { return Ok(false) };
                let Message::Text(text) = msg? else { continue };
                let Ok(v) = serde_json::from_str::<Value>(&text) else { continue };
                match v["messageType"].as_str() {
                    Some("hello") => {
                        sub.uaid = v["uaid"].as_str().unwrap_or_default().to_owned();
                        let reg = json!({
                            "messageType": "register",
                            "channelID": sub.channel_id,
                            "key": vapid_key,
                        });
                        write.send(Message::Text(reg.to_string())).await?;
                    }
                    Some("register") => {
                        if let Some(ep) = v["pushEndpoint"].as_str() {
                            sub.endpoint = ep.to_owned();
                            if sink.add(PushEvent::Registered(sub.clone())).is_err() {
                                return Ok(true);
                            }
                        }
                    }
                    Some("notification") => {
                        if let (Some(data), Some(channel), Some(version)) =
                            (v["data"].as_str(), v["channelID"].as_str(), v["version"].as_str())
                        {
                            if let Ok(bytes) = B64.decode(data.trim_end_matches('=')) {
                                if let Ok(plain) = decrypt(sub, &bytes) {
                                    let _ = sink.add(PushEvent::Notification(
                                        String::from_utf8_lossy(&plain).into_owned(),
                                    ));
                                }
                            }
                            let ack = json!({
                                "messageType": "ack",
                                "updates": [{"channelID": channel, "version": version, "code": 100}],
                            });
                            write.send(Message::Text(ack.to_string())).await?;
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

/// Starts (or resumes, when `saved` is given) a desktop web-push subscription.
pub async fn push_start(
    vapid_key: String,
    saved: Option<PushSubscription>,
    sink: StreamSink<PushEvent>,
) -> anyhow::Result<()> {
    push_stop();
    let (tx, mut rx) = unbounded_channel::<()>();
    *STOP.lock().unwrap() = Some(tx);

    let mut sub = saved.unwrap_or_else(fresh_subscription);
    let mut attempt = 0u32;
    loop {
        match session(&vapid_key, &mut sub, &sink, &mut rx).await {
            Ok(true) => break,
            Ok(false) => {
                let _ = sink.add(PushEvent::Closed("disconnected".into()));
            }
            Err(e) => {
                if sink.add(PushEvent::Closed(e.to_string())).is_err() {
                    break;
                }
            }
        }
        attempt = attempt.saturating_add(1);
        let delay = Duration::from_secs((2u64 << attempt.min(5)).min(120));
        tokio::select! {
            _ = tokio::time::sleep(delay) => {}
            _ = rx.recv() => break,
        }
    }
    Ok(())
}

pub fn push_stop() {
    if let Some(tx) = STOP.lock().unwrap().take() {
        let _ = tx.send(());
    }
}
