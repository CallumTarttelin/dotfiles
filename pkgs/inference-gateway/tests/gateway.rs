use anyhow::Result;
use axum::{
    Router,
    body::{Body, Bytes},
    extract::State,
    http::{HeaderMap, Response, StatusCode},
    routing::post,
};
use base64::{Engine, engine::general_purpose::STANDARD};
use futures_util::StreamExt;
use inference_gateway::{
    gateway::{Config, Runtime, application},
    journal::Event,
    provision::digest,
};
use serde_json::{Value, json};
use std::{
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::Duration,
};
use tokio::{
    sync::{Semaphore, mpsc},
    task::JoinHandle,
};
use tokio_stream::wrappers::ReceiverStream;

#[derive(Clone, Copy)]
enum Mode {
    Valid,
    Failed,
    Missing,
    Fragmented,
    ControlError,
    InvalidJson,
    Retry,
    Truncated,
    DelayedEof,
    TerminalTruncated,
    TerminalLargeTail,
    SessionRetry,
    SessionAlwaysRefused,
    OtherPrecondition,
}
struct Mock {
    mode: Mode,
    release: Semaphore,
    eof_release: Semaphore,
    seen: AtomicUsize,
    audit_seen: AtomicBool,
    audit_attempts: AtomicUsize,
    headers: Mutex<HeaderMap>,
    body: Mutex<Bytes>,
}

async fn inference(
    State(mock): State<Arc<Mock>>,
    uri: axum::http::Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response<Body> {
    let attempt = mock.seen.fetch_add(1, Ordering::SeqCst);
    *mock.headers.lock().unwrap() = headers;
    *mock.body.lock().unwrap() = body;
    if matches!(
        mock.mode,
        Mode::SessionAlwaysRefused | Mode::OtherPrecondition
    ) || (matches!(mock.mode, Mode::SessionRetry) && attempt < 2)
    {
        let kind = if matches!(mock.mode, Mode::OtherPrecondition) {
            "other_precondition"
        } else {
            "session_not_accepted"
        };
        let mut response = Response::new(Body::from(json!({"error":{"type":kind}}).to_string()));
        *response.status_mut() = StatusCode::PRECONDITION_FAILED;
        response
            .headers_mut()
            .insert("x-receipt-id", "rcpt-refused".parse().unwrap());
        return response;
    }
    let (tx, rx) = mpsc::channel(2);
    let worker = mock.clone();
    let terminal = match uri.path() {
        "/v1/responses" if matches!(mock.mode, Mode::DelayedEof | Mode::TerminalTruncated) => {
            "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
        }
        "/v1/messages" => "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
        _ => "data: [DONE]\n\n",
    };
    tokio::spawn(async move {
        let _ = tx
            .send(Ok::<_, std::io::Error>(Bytes::from_static(
                b"data: first\n\n",
            )))
            .await;
        let permit = worker.release.acquire().await.unwrap();
        permit.forget();
        let chunk = if matches!(worker.mode, Mode::Truncated) {
            Err(std::io::Error::other("truncated"))
        } else {
            Ok(Bytes::from_static(terminal.as_bytes()))
        };
        let _ = tx.send(chunk).await;
        if matches!(
            worker.mode,
            Mode::DelayedEof | Mode::TerminalTruncated | Mode::TerminalLargeTail
        ) {
            let permit = worker.eof_release.acquire().await.unwrap();
            permit.forget();
            let tail = if matches!(worker.mode, Mode::TerminalTruncated) {
                Err(std::io::Error::other("truncated after terminal event"))
            } else if matches!(worker.mode, Mode::TerminalLargeTail) {
                Ok(Bytes::from(vec![b' '; 1024 * 1024 + 1]))
            } else {
                Ok(Bytes::from_static(b": trailer\n\n"))
            };
            let _ = tx.send(tail).await;
        }
    });
    let mut response = Response::new(Body::from_stream(ReceiverStream::new(rx)));
    response
        .headers_mut()
        .insert("content-type", "text/event-stream".parse().unwrap());
    if !matches!(mock.mode, Mode::Missing) {
        response
            .headers_mut()
            .insert("x-receipt-id", "rcpt-test".parse().unwrap());
    }
    response
}

async fn audit(State(mock): State<Arc<Mock>>, headers: HeaderMap) -> Response<Body> {
    assert_eq!(headers["authorization"], "Bearer upstream-secret");
    mock.audit_seen.store(true, Ordering::SeqCst);
    let attempt = mock.audit_attempts.fetch_add(1, Ordering::SeqCst);
    let status = if matches!(mock.mode, Mode::ControlError) {
        StatusCode::BAD_GATEWAY
    } else if matches!(mock.mode, Mode::Retry) && attempt < 2 {
        StatusCode::NOT_FOUND
    } else {
        StatusCode::OK
    };
    let failed = matches!(
        mock.mode,
        Mode::Failed | Mode::SessionAlwaysRefused | Mode::OtherPrecondition
    );
    let data = json!({"verdict": {"verified": !failed,
        "failed": if failed {1} else {0}}, "checks": []});
    let bytes = if matches!(mock.mode, Mode::InvalidJson) {
        b"not json".to_vec()
    } else {
        serde_json::to_vec(&data).unwrap()
    };
    let mut response = if matches!(mock.mode, Mode::Fragmented) {
        let (tx, rx) = mpsc::channel(2);
        tokio::spawn(async move {
            let _ = tx
                .send(Ok::<_, std::io::Error>(Bytes::copy_from_slice(
                    &bytes[..10],
                )))
                .await;
            tokio::time::sleep(Duration::from_millis(10)).await;
            let _ = tx.send(Ok(Bytes::copy_from_slice(&bytes[10..]))).await;
        });
        Response::new(Body::from_stream(ReceiverStream::new(rx)))
    } else {
        Response::new(Body::from(bytes))
    };
    *response.status_mut() = status;
    response
}

struct Fixture {
    state: tempfile::TempDir,
    mock: Arc<Mock>,
    url: String,
    http: reqwest::Client,
    runtime: Runtime,
    tasks: Vec<JoinHandle<()>>,
}
impl Fixture {
    async fn new(mode: Mode) -> Result<Self> {
        Self::with_registry(mode, false).await
    }
    async fn with_registry(mode: Mode, dynamic: bool) -> Result<Self> {
        let state = tempfile::tempdir()?;
        let registry_path = if dynamic {
            let path = state.path().join("keys/keys.json");
            inference_gateway::keys::initialize(
                &path,
                nix::unistd::Gid::current(),
                vec![inference_gateway::keys::bootstrap(
                    "hermes",
                    "client-secret",
                    vec!["phala".into()],
                )],
            )?;
            Some(path)
        } else {
            None
        };
        let mock = Arc::new(Mock {
            mode,
            release: Semaphore::new(0),
            eof_release: Semaphore::new(0),
            seen: AtomicUsize::new(0),
            audit_seen: AtomicBool::new(false),
            audit_attempts: AtomicUsize::new(0),
            headers: Mutex::new(HeaderMap::new()),
            body: Mutex::new(Bytes::new()),
        });
        let upstream = Router::new()
            .route("/v1/chat/completions", post(inference))
            .route("/v1/responses", post(inference))
            .route("/v1/messages", post(inference))
            .route("/receipts/{id}/verify", post(audit))
            .with_state(mock.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let upstream_url = format!("http://{}", listener.local_addr()?);
        let upstream_task = tokio::spawn(async move {
            axum::serve(listener, upstream).await.unwrap();
        });
        let config: Config = serde_json::from_value(json!({
            "client_keys_file": registry_path,
            "clients": {"hermes": {"sha256": digest("client-secret"), "routes": ["phala"]},
                        "both": {"sha256": digest("both-secret"), "routes": ["phala", "openai"]}},
            "routes": {
                "phala": {"url": format!("{upstream_url}/v1"), "token": "upstream-secret", "models": ["deepseek-test"]},
                "openai": {"url": format!("{upstream_url}/v1"), "token": "subscription-secret"}
            }, "pap_control": upstream_url
        }))?;
        let (gateway, runtime) = application(config, state.path())?;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let url = format!("http://{}", listener.local_addr()?);
        let gateway_task = tokio::spawn(async move {
            axum::serve(listener, gateway).await.unwrap();
        });
        Ok(Self {
            state,
            mock,
            url,
            runtime,
            http: reqwest::Client::builder().no_proxy().build()?,
            tasks: vec![upstream_task, gateway_task],
        })
    }
    async fn call(&self, endpoint: &str) -> Result<reqwest::Response> {
        Ok(self.http.post(format!("{}/phala/v1/{endpoint}", self.url))
            .bearer_auth("client-secret").header("x-private-key", "never-forward")
            .json(&json!({"model": "deepseek-test", "messages": [{"role": "user", "content": "private prompt"}]})).send().await?)
    }
    async fn rows(&self) -> Result<Vec<Event>> {
        for _ in 0..200 {
            let paths = inference_gateway::journal::files_with_extension(
                &self.state.path().join("journal"),
                "jsonl",
            )?;
            if !paths.is_empty() {
                return read_events(&paths[0]);
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        anyhow::bail!("journal was not sealed")
    }
    async fn finish(&self) {
        self.runtime.finish().await;
    }
}

#[tokio::test]
async fn new_keys_work_and_revocation_applies_without_restarting() -> Result<()> {
    let fixture = Fixture::with_registry(Mode::Valid, true).await?;
    let registry = fixture.state.path().join("keys/keys.json");
    let (_, token) = inference_gateway::keys::create(&registry, "laptop", vec!["phala".into()])?;
    let body = json!({"model": "deepseek-test", "input": "hello"});
    let denied = fixture
        .http
        .post(format!("{}/openai/v1/responses", fixture.url))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?;
    assert_eq!(denied.status(), StatusCode::FORBIDDEN);
    fixture.mock.release.add_permits(1);
    let response = fixture
        .http
        .post(format!("{}/phala/v1/responses", fixture.url))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?;
    assert_eq!(response.status(), StatusCode::OK);
    response.bytes().await?;
    assert!(
        fixture
            .rows()
            .await?
            .iter()
            .all(|event| event.client == "laptop")
    );
    inference_gateway::keys::revoke(&registry, "laptop")?;
    let denied = fixture
        .http
        .post(format!("{}/phala/v1/responses", fixture.url))
        .bearer_auth(&token)
        .json(&body)
        .send()
        .await?;
    assert_eq!(denied.status(), StatusCode::UNAUTHORIZED);
    assert_eq!(fixture.mock.seen.load(Ordering::SeqCst), 1);
    // The static legacy client map must never be used as a fallback on registry errors.
    std::fs::write(&registry, b"broken registry")?;
    assert_eq!(
        fixture.call("responses").await?.status(),
        StatusCode::SERVICE_UNAVAILABLE
    );
    std::fs::remove_file(&registry)?;
    assert_eq!(
        fixture.call("responses").await?.status(),
        StatusCode::SERVICE_UNAVAILABLE
    );
    fixture.finish().await;
    Ok(())
}
impl Drop for Fixture {
    fn drop(&mut self) {
        self.runtime.cancel();
        self.mock.release.add_permits(100);
        self.mock.eof_release.add_permits(100);
        for task in &self.tasks {
            task.abort();
        }
    }
}
fn read_events(path: &Path) -> Result<Vec<Event>> {
    std::fs::read_to_string(path)?
        .lines()
        .map(|line| Ok(serde_json::from_str(line)?))
        .collect()
}
fn audit_state(rows: &[Event]) -> Result<String> {
    let audit = rows.iter().find(|r| r.kind == "audit").unwrap();
    Ok(
        serde_json::from_str::<Value>(&audit.data_json)?["audit_state"]
            .as_str()
            .unwrap()
            .to_owned(),
    )
}

#[tokio::test]
async fn streams_before_audit_and_preserves_exact_bytes_without_tokens() -> Result<()> {
    let fixture = Fixture::new(Mode::Valid).await?;
    let response = fixture.call("chat/completions").await?;
    assert_eq!(response.status(), StatusCode::OK);
    let mut stream = response.bytes_stream();
    let first = tokio::time::timeout(Duration::from_secs(1), stream.next())
        .await?
        .unwrap()?;
    assert_eq!(first.as_ref(), b"data: first\n\n");
    assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
    fixture.mock.release.add_permits(1);
    let mut received = first.to_vec();
    while let Some(chunk) = stream.next().await {
        received.extend_from_slice(&chunk?);
    }
    let rows = fixture.rows().await?;
    assert_eq!(audit_state(&rows)?, "verified");
    let mut captured = Vec::new();
    for event in &rows {
        if event.kind == "response_chunk" {
            let value: Value = serde_json::from_str(&event.data_json)?;
            captured.extend(STANDARD.decode(value["body_base64"].as_str().unwrap())?);
        }
    }
    assert_eq!(captured, received);
    {
        let headers = fixture.mock.headers.lock().unwrap();
        assert_eq!(headers["authorization"], "Bearer upstream-secret");
        assert!(!headers.contains_key("x-private-key"));
    }
    assert!(
        fixture
            .mock
            .body
            .lock()
            .unwrap()
            .windows(14)
            .any(|s| s == b"private prompt")
    );
    let logged = serde_json::to_string(&rows)?;
    for secret in ["client-secret", "upstream-secret", "never-forward"] {
        assert!(!logged.contains(secret));
    }
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn response_protocol_and_audit_failure_states() -> Result<()> {
    for (mode, expected) in [
        (Mode::Failed, "failed"),
        (Mode::Missing, "failed"),
        (Mode::Fragmented, "verified"),
        (Mode::ControlError, "unavailable"),
        (Mode::InvalidJson, "unavailable"),
        (Mode::Retry, "verified"),
    ] {
        let fixture = Fixture::new(mode).await?;
        fixture.mock.release.add_permits(1);
        let response = fixture.call("responses").await?;
        assert_eq!(response.status(), StatusCode::OK);
        assert!(response.bytes().await?.ends_with(b"data: [DONE]\n\n"));
        assert_eq!(audit_state(&fixture.rows().await?)?, expected);
        if matches!(mode, Mode::Retry) {
            assert_eq!(fixture.mock.audit_attempts.load(Ordering::SeqCst), 3);
        }
        fixture.finish().await;
    }
    Ok(())
}

#[tokio::test]
async fn rejects_auth_route_model_and_backend_control_requests_before_forwarding() -> Result<()> {
    let fixture = Fixture::new(Mode::Valid).await?;
    for (path, token, model, expected) in [
        ("/phala/v1/chat/completions", "wrong", "deepseek-test", 401),
        (
            "/openai/v1/chat/completions",
            "client-secret",
            "deepseek-test",
            403,
        ),
        (
            "/phala/v1/chat/completions",
            "client-secret",
            "other-model",
            403,
        ),
        (
            "/phala/v1/aci/receipts",
            "client-secret",
            "deepseek-test",
            404,
        ),
        (
            "/phala/v1/responses?forward=elsewhere",
            "client-secret",
            "deepseek-test",
            400,
        ),
    ] {
        let response = fixture
            .http
            .post(format!("{}{path}", fixture.url))
            .bearer_auth(token)
            .json(&json!({"model": model}))
            .send()
            .await?;
        assert_eq!(response.status().as_u16(), expected);
    }
    assert_eq!(fixture.mock.seen.load(Ordering::SeqCst), 0);
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn interrupted_upstream_resets_the_stream_and_never_gets_a_verified_audit() -> Result<()> {
    let fixture = Fixture::new(Mode::Truncated).await?;
    let response = fixture.call("responses").await?;
    let mut stream = response.bytes_stream();
    assert!(stream.next().await.unwrap().is_ok());
    fixture.mock.release.add_permits(1);
    assert!(stream.next().await.unwrap().is_err());
    assert_eq!(audit_state(&fixture.rows().await?)?, "unavailable");
    assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn dropped_client_is_persisted_as_incomplete() -> Result<()> {
    let fixture = Fixture::new(Mode::Valid).await?;
    let response = fixture.call("responses").await?;
    let mut stream = response.bytes_stream();
    assert!(stream.next().await.unwrap().is_ok());
    drop(stream);
    assert_eq!(audit_state(&fixture.rows().await?)?, "unavailable");
    assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn closing_at_protocol_end_still_captures_http_tail_and_audits() -> Result<()> {
    for endpoint in ["chat/completions", "responses", "messages"] {
        let fixture = Fixture::new(Mode::DelayedEof).await?;
        fixture.mock.release.add_permits(1);
        let mut stream = fixture.call(endpoint).await?.bytes_stream();
        let mut received = Vec::new();
        loop {
            received.extend_from_slice(&stream.next().await.unwrap()?);
            if String::from_utf8_lossy(&received).contains(match endpoint {
                "responses" => "response.completed",
                "messages" => "message_stop",
                _ => "[DONE]",
            }) {
                break;
            }
        }
        drop(stream); // SDKs stop here, without polling HTTP EOF.
        tokio::time::sleep(Duration::from_millis(30)).await;
        assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
        fixture.mock.eof_release.add_permits(1);
        let rows = fixture.rows().await?;
        assert_eq!(audit_state(&rows)?, "verified");
        let captured: Vec<u8> = rows
            .iter()
            .filter(|r| r.kind == "response_chunk")
            .flat_map(|r| {
                STANDARD
                    .decode(
                        serde_json::from_str::<Value>(&r.data_json).unwrap()["body_base64"]
                            .as_str()
                            .unwrap(),
                    )
                    .unwrap()
            })
            .collect();
        assert!(captured.ends_with(b": trailer\n\n"));
        assert!(rows.iter().any(|r| r.kind == "response_end"));
        assert!(!rows.iter().any(|r| r.kind == "transport_error"));
        let delivery: Value = serde_json::from_str(
            &rows
                .iter()
                .find(|r| r.kind == "delivery_end")
                .unwrap()
                .data_json,
        )?;
        assert_eq!(
            delivery,
            json!({"complete":true,"completion":"protocol_end"})
        );
        fixture.finish().await;
    }
    Ok(())
}

#[tokio::test]
async fn terminal_marker_does_not_excuse_a_truncated_upstream() -> Result<()> {
    let fixture = Fixture::new(Mode::TerminalTruncated).await?;
    fixture.mock.release.add_permits(1);
    let mut stream = fixture.call("chat/completions").await?.bytes_stream();
    while !stream
        .next()
        .await
        .unwrap()?
        .windows(6)
        .any(|w| w == b"[DONE]")
    {}
    drop(stream);
    tokio::time::sleep(Duration::from_millis(30)).await;
    fixture.mock.eof_release.add_permits(1);
    assert_eq!(audit_state(&fixture.rows().await?)?, "unavailable");
    assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn terminal_marker_does_not_allow_an_unbounded_drain() -> Result<()> {
    let fixture = Fixture::new(Mode::DelayedEof).await?;
    fixture.mock.release.add_permits(1);
    let mut stream = fixture.call("chat/completions").await?.bytes_stream();
    while !stream
        .next()
        .await
        .unwrap()?
        .windows(6)
        .any(|w| w == b"[DONE]")
    {}
    drop(stream);
    tokio::time::sleep(Duration::from_millis(5200)).await;
    let rows = fixture.rows().await?;
    assert_eq!(audit_state(&rows)?, "unavailable");
    assert!(
        rows.iter()
            .any(|r| r.kind == "transport_error"
                && r.data_json.contains("PostCompletionDrainTimeout"))
    );
    assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn terminal_marker_does_not_allow_an_oversized_drain() -> Result<()> {
    let fixture = Fixture::new(Mode::TerminalLargeTail).await?;
    fixture.mock.release.add_permits(1);
    let mut stream = fixture.call("chat/completions").await?.bytes_stream();
    while !stream
        .next()
        .await
        .unwrap()?
        .windows(6)
        .any(|w| w == b"[DONE]")
    {}
    drop(stream);
    tokio::time::sleep(Duration::from_millis(30)).await;
    fixture.mock.eof_release.add_permits(1);
    let rows = fixture.rows().await?;
    assert_eq!(audit_state(&rows)?, "unavailable");
    assert!(
        rows.iter().any(
            |r| r.kind == "transport_error" && r.data_json.contains("PostCompletionDrainLimit")
        )
    );
    assert!(!fixture.mock.audit_seen.load(Ordering::SeqCst));
    fixture.finish().await;
    Ok(())
}

#[tokio::test]
async fn explicit_session_refusals_are_retried_boundedly_and_recorded() -> Result<()> {
    for (mode, status, retries, verdict) in [
        (Mode::SessionRetry, StatusCode::OK, 2, "verified"),
        (
            Mode::SessionAlwaysRefused,
            StatusCode::PRECONDITION_FAILED,
            2,
            "failed",
        ),
        (
            Mode::OtherPrecondition,
            StatusCode::PRECONDITION_FAILED,
            0,
            "failed",
        ),
    ] {
        let fixture = Fixture::new(mode).await?;
        fixture.mock.release.add_permits(1);
        let response = fixture.call("responses").await?;
        assert_eq!(response.status(), status);
        let bytes = response.bytes().await?;
        if status == StatusCode::PRECONDITION_FAILED {
            let data: Value = serde_json::from_slice(&bytes)?;
            assert!(data["error"]["type"].is_string());
        }
        let rows = fixture.rows().await?;
        assert_eq!(audit_state(&rows)?, verdict);
        assert_eq!(fixture.mock.seen.load(Ordering::SeqCst), retries + 1);
        assert_eq!(
            rows.iter().filter(|r| r.kind == "upstream_retry").count(),
            retries
        );
        for event in rows.iter().filter(|r| r.kind == "upstream_retry") {
            let data: Value = serde_json::from_str(&event.data_json)?;
            let body = STANDARD.decode(data["body_base64"].as_str().unwrap())?;
            assert_eq!(
                serde_json::from_slice::<Value>(&body)?["error"]["type"],
                "session_not_accepted"
            );
            assert_eq!(data["receipt_id"], "rcpt-refused");
        }
        fixture.finish().await;
    }
    Ok(())
}

#[tokio::test]
async fn openai_and_caller_pinned_requests_are_never_replayed() -> Result<()> {
    for (route, pinned) in [("openai", false), ("phala", true)] {
        let fixture = Fixture::new(Mode::SessionAlwaysRefused).await?;
        let mut body = json!({"model":"deepseek-test","input":"hello"});
        if pinned {
            body["provider"] = json!({"aci_session_ids":["user-pin"]});
        }
        let response = fixture
            .http
            .post(format!("{}/{route}/v1/responses", fixture.url))
            .bearer_auth("both-secret")
            .json(&body)
            .send()
            .await?;
        assert_eq!(response.status(), StatusCode::PRECONDITION_FAILED);
        let bytes = response.bytes().await?;
        assert_eq!(
            serde_json::from_slice::<Value>(&bytes)?["error"]["type"],
            "session_not_accepted"
        );
        let rows = fixture.rows().await?;
        assert_eq!(fixture.mock.seen.load(Ordering::SeqCst), 1);
        assert!(!rows.iter().any(|r| r.kind == "upstream_retry"));
        fixture.finish().await;
    }
    Ok(())
}

#[tokio::test]
async fn cancellation_seals_an_unavailable_audit() -> Result<()> {
    let fixture = Fixture::new(Mode::Valid).await?;
    let response = fixture.call("responses").await?;
    let mut stream = response.bytes_stream();
    assert!(stream.next().await.unwrap().is_ok());
    fixture.runtime.cancel();
    assert!(stream.next().await.unwrap().is_err());
    assert_eq!(audit_state(&fixture.rows().await?)?, "unavailable");
    fixture.finish().await;
    Ok(())
}
