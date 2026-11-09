use crate::frb_generated::StreamSink;
use futures_util::{SinkExt, StreamExt};
use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::time::Duration;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio_tungstenite::tungstenite::Message;

pub enum GatewayEvent {
    Open,
    Text(String),
    Closed(String),
}

enum Command {
    Send(String),
    Close,
}

static HANDLE: Lazy<Mutex<Option<UnboundedSender<Command>>>> = Lazy::new(|| Mutex::new(None));

/// Opens the events websocket and keeps it alive (ping + exponential backoff reconnect)
/// until `gateway_disconnect` is called.
pub async fn gateway_connect(
    url: String,
    sink: StreamSink<GatewayEvent>,
) -> anyhow::Result<()> {
    gateway_disconnect();

    let (tx, mut rx) = unbounded_channel::<Command>();
    *HANDLE.lock().unwrap() = Some(tx);

    let mut attempt: u32 = 0;

    'outer: loop {
        match tokio_tungstenite::connect_async(url.as_str()).await {
            Ok((stream, _)) => {
                attempt = 0;
                if sink.add(GatewayEvent::Open).is_err() {
                    break;
                }

                let (mut write, mut read) = stream.split();
                let mut ping = tokio::time::interval(Duration::from_secs(20));
                ping.tick().await;

                loop {
                    tokio::select! {
                        _ = ping.tick() => {
                            if write.send(Message::Text("{\"type\":\"Ping\",\"data\":0}".into())).await.is_err() {
                                let _ = sink.add(GatewayEvent::Closed("ping failed".into()));
                                break;
                            }
                        }
                        cmd = rx.recv() => {
                            match cmd {
                                Some(Command::Send(text)) => {
                                    if write.send(Message::Text(text)).await.is_err() {
                                        let _ = sink.add(GatewayEvent::Closed("send failed".into()));
                                        break;
                                    }
                                }
                                Some(Command::Close) | None => {
                                    let _ = write.close().await;
                                    break 'outer;
                                }
                            }
                        }
                        msg = read.next() => {
                            match msg {
                                Some(Ok(Message::Text(text))) => {
                                    if sink.add(GatewayEvent::Text(text)).is_err() {
                                        break 'outer;
                                    }
                                }
                                Some(Ok(Message::Close(frame))) => {
                                    let reason = frame.map(|f| f.reason.to_string()).unwrap_or_default();
                                    let _ = sink.add(GatewayEvent::Closed(reason));
                                    break;
                                }
                                Some(Ok(_)) => {}
                                Some(Err(e)) => {
                                    let _ = sink.add(GatewayEvent::Closed(e.to_string()));
                                    break;
                                }
                                None => {
                                    let _ = sink.add(GatewayEvent::Closed("stream ended".into()));
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            Err(e) => {
                if sink.add(GatewayEvent::Closed(e.to_string())).is_err() {
                    break;
                }
            }
        }

        attempt = attempt.saturating_add(1);
        let delay = Duration::from_millis((500u64 << attempt.min(5)).min(15_000));
        tokio::select! {
            _ = tokio::time::sleep(delay) => {}
            cmd = rx.recv() => {
                if matches!(cmd, Some(Command::Close) | None) {
                    break 'outer;
                }
            }
        }
    }

    Ok(())
}

pub fn gateway_send(text: String) {
    if let Some(tx) = HANDLE.lock().unwrap().as_ref() {
        let _ = tx.send(Command::Send(text));
    }
}

pub fn gateway_disconnect() {
    if let Some(tx) = HANDLE.lock().unwrap().take() {
        let _ = tx.send(Command::Close);
    }
}
