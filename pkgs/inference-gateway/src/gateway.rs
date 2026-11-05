//! Streaming HTTP inference, durable capture, and independent post-stream audits.
use crate::journal::{AsyncJournal, recover};
use crate::provision::digest;
use anyhow::Result;
use axum::{
    Router,
    body::{Body, Bytes, to_bytes},
    extract::{Request, State},
    http::{HeaderMap, HeaderValue, Method, Response, StatusCode},
    response::IntoResponse,
};
use base64::{Engine, engine::general_purpose::STANDARD};
use futures_util::{Stream, StreamExt, stream::BoxStream};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io,
    path::Path,
    pin::Pin,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    task::{Context, Poll},
    time::{Duration, Instant},
};
use subtle::ConstantTimeEq;
use tokio::sync::{mpsc, oneshot};
use tokio_stream::wrappers::ReceiverStream;
use tokio_util::{sync::CancellationToken, task::TaskTracker};

const ENDPOINTS: &[&str] = &[
    "chat/completions",
    "responses",
    "messages",
    "embeddings",
    "models",
];
const SAFE_HEADERS: &[&str] = &[
    "content-type",
    "content-encoding",
    "cache-control",
    "retry-after",
    "x-receipt-id",
    "x-aci-identity",
    "x-aci-keyset-digest",
    "x-request-id",
];

// Deliberately not Debug: these objects contain upstream credentials.
#[derive(Clone, Deserialize)]
pub struct Config {
    pub clients: BTreeMap<String, Client>,
    pub routes: BTreeMap<String, Route>,
    pub pap_control: String,
    #[serde(default)]
    pub client_keys_file: Option<std::path::PathBuf>,
}
#[derive(Clone, Deserialize)]
pub struct Client {
    pub sha256: String,
    pub routes: Vec<String>,
}
#[derive(Clone, Deserialize)]
pub struct Route {
    pub url: String,
    pub token: String,
    #[serde(default)]
    pub models: Vec<String>,
}

#[derive(Clone, Default)]
pub struct Runtime {
    tasks: TaskTracker,
    cancel: CancellationToken,
}
impl Runtime {
    pub fn cancel(&self) {
        self.cancel.cancel();
    }
    pub async fn finish(&self) {
        self.tasks.close();
        if tokio::time::timeout(Duration::from_secs(35), self.tasks.wait())
            .await
            .is_err()
        {
            self.cancel();
            // Cancellation paths persist unavailable audits and seal their journals.
            self.tasks.wait().await;
        }
    }
}

struct Gateway {
    config: Config,
    journals: std::path::PathBuf,
    http: reqwest::Client,
    runtime: Runtime,
}

pub fn application(config: Config, state: &Path) -> Result<(Router, Runtime)> {
    let journals = state.join("journal");
    recover(&journals)?;
    let runtime = Runtime::default();
    let gateway = Arc::new(Gateway {
        config,
        journals,
        runtime: runtime.clone(),
        http: reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(15))
            .read_timeout(Duration::from_secs(300))
            .build()?,
    });
    let router = Router::new().fallback(handle).with_state(gateway);
    Ok((router, runtime))
}

type HttpError = (StatusCode, &'static str);
fn internal(_: anyhow::Error) -> HttpError {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        "Inference journal unavailable",
    )
}

async fn authenticate(
    config: &Config,
    headers: &HeaderMap,
    route: &str,
) -> Result<String, HttpError> {
    let token = headers
        .get("authorization")
        .and_then(|x| x.to_str().ok())
        .and_then(|x| x.strip_prefix("Bearer "))
        .filter(|x| !x.is_empty())
        .ok_or((StatusCode::UNAUTHORIZED, "Unauthorized"))?;
    let hashed = digest(token);
    if let Some(path) = config.client_keys_file.clone() {
        let registry = tokio::task::spawn_blocking(move || crate::keys::load(&path))
            .await
            .map_err(|_| {
                (
                    StatusCode::SERVICE_UNAVAILABLE,
                    "Client-key registry unavailable",
                )
            })?
            .map_err(|_| {
                (
                    StatusCode::SERVICE_UNAVAILABLE,
                    "Client-key registry unavailable",
                )
            })?;
        let key = registry
            .authenticate(&hashed)
            .ok_or((StatusCode::UNAUTHORIZED, "Unauthorized"))?;
        return if key.routes.iter().any(|r| r == route) {
            Ok(key.name.clone())
        } else {
            Err((
                StatusCode::FORBIDDEN,
                "Route is not enabled for this client",
            ))
        };
    }
    for (name, client) in &config.clients {
        if bool::from(hashed.as_bytes().ct_eq(client.sha256.as_bytes())) {
            return if client.routes.iter().any(|x| x == route) {
                Ok(name.clone())
            } else {
                Err((
                    StatusCode::FORBIDDEN,
                    "Route is not enabled for this client",
                ))
            };
        }
    }
    Err((StatusCode::UNAUTHORIZED, "Unauthorized"))
}

async fn handle(
    State(state): State<Arc<Gateway>>,
    request: Request,
) -> Result<Response<Body>, HttpError> {
    let (route, endpoint) = request
        .uri()
        .path()
        .strip_prefix('/')
        .and_then(|x| x.split_once("/v1/"))
        .ok_or((StatusCode::NOT_FOUND, "Not found"))?;
    if !ENDPOINTS.contains(&endpoint) || !state.config.routes.contains_key(route) {
        return Err((StatusCode::NOT_FOUND, "Not found"));
    }
    let client = authenticate(&state.config, request.headers(), route).await?;
    let is_post = endpoint != "models";
    if request.method() != (if is_post { Method::POST } else { Method::GET }) {
        let mut response = (StatusCode::METHOD_NOT_ALLOWED, "Method not allowed").into_response();
        response.headers_mut().insert(
            "allow",
            HeaderValue::from_static(if is_post { "POST" } else { "GET" }),
        );
        return Ok(response);
    }
    if request.uri().query().is_some() || request.headers().contains_key("upgrade") {
        return Err((
            StatusCode::BAD_REQUEST,
            "Use HTTP inference without query parameters or WebSocket upgrades",
        ));
    }
    let (route, endpoint) = (route.to_owned(), endpoint.to_owned());
    let headers = request.headers().clone();
    let body = to_bytes(request.into_body(), 32 * 1024 * 1024)
        .await
        .map_err(|_| {
            (
                StatusCode::PAYLOAD_TOO_LARGE,
                "Request body exceeds the limit or could not be read",
            )
        })?;
    let model = if is_post {
        let value: Value = serde_json::from_slice(&body).map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                "Expected a JSON object with a model",
            )
        })?;
        let model = value
            .as_object()
            .and_then(|v| v.get("model"))
            .and_then(Value::as_str)
            .ok_or((
                StatusCode::BAD_REQUEST,
                "Expected a JSON object with a model",
            ))?
            .to_owned();
        let models = &state.config.routes[&route].models;
        if !models.is_empty() && !models.contains(&model) {
            return Err((StatusCode::FORBIDDEN, "Model is not enabled on this route"));
        }
        Some(model)
    } else {
        None
    };
    let journal = AsyncJournal::new(state.journals.clone(), route.clone(), client)
        .await
        .map_err(internal)?;
    journal
        .emit(
            "request",
            json!({"method": if is_post {"POST"} else {"GET"},
        "endpoint": endpoint, "model": model, "body_base64": STANDARD.encode(&body)}),
        )
        .await
        .map_err(internal)?;
    let upstream = &state.config.routes[&route];
    let started = Instant::now();
    let retry_session = route == "phala"
        && is_post
        && serde_json::from_slice::<Value>(&body)
            .ok()
            .is_some_and(|v| {
                v.get("provider")
                    .and_then(|p| p.get("aci_session_ids"))
                    .is_none()
            });
    let mut outgoing = state
        .http
        .request(
            if is_post { Method::POST } else { Method::GET },
            format!("{}/{}", upstream.url, endpoint),
        )
        .bearer_auth(&upstream.token)
        .header("content-type", "application/json")
        .header("accept-encoding", "identity");
    if !body.is_empty() {
        outgoing = outgoing.body(body);
    }
    for name in ["openai-beta", "anthropic-version", "anthropic-beta"] {
        if let Some(value) = headers.get(name) {
            outgoing = outgoing.header(name, value);
        }
    }
    let remote = match send_with_session_retry(&state, outgoing, &journal, retry_session).await {
        Ok(remote) => remote,
        Err(label) => {
            journal
                .emit("transport_error", json!({"error": label}))
                .await
                .map_err(internal)?;
            tracing::error!(request_id = %journal.request_id, error = label, "upstream request failed");
            spawn_finish(&state, journal, route == "phala" && is_post, None, false);
            return Err((StatusCode::BAD_GATEWAY, "Inference upstream unavailable"));
        }
    };
    let status = remote.status;
    let receipt = remote
        .headers
        .get("x-receipt-id")
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);
    let mut response_headers = HeaderMap::new();
    let mut recorded_headers = BTreeMap::new();
    for name in SAFE_HEADERS {
        if let Some(value) = remote.headers.get(*name) {
            response_headers.insert(*name, value.clone());
            if let Ok(value) = value.to_str() {
                recorded_headers.insert(*name, value);
            }
        }
    }
    journal.emit("response_start", json!({"status": status.as_u16(), "headers": recorded_headers,
        "receipt_id": receipt, "audit_state": if route == "phala" && is_post {"pending"} else {"not_applicable"}})).await.map_err(internal)?;
    response_headers.insert(
        "x-inference-request-id",
        HeaderValue::from_str(&journal.request_id).unwrap(),
    );
    // A client may finish at a protocol terminal event rather than HTTP EOF.
    // Only the consumer marks it delivered; a marker merely queued is insufficient.
    let completion = remote
        .headers
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .filter(|v| {
            v.split(';')
                .next()
                .unwrap_or("")
                .trim()
                .eq_ignore_ascii_case("text/event-stream")
        })
        .filter(|_| {
            remote
                .headers
                .get("content-encoding")
                .is_none_or(|v| v == "identity")
        })
        .and_then(|_| crate::sse::Completion::new(&endpoint));
    let protocol_end = Arc::new(AtomicBool::new(false));
    let worker_protocol_end = protocol_end.clone();
    let (sender, receiver) = mpsc::channel(8);
    let (ack, delivered) = oneshot::channel();
    let failed = Arc::new(AtomicBool::new(false));
    let worker_failed = failed.clone();
    let worker_state = state.clone();
    state.runtime.tasks.spawn(async move {
        let result = forward(remote.stream, sender, delivered, &journal, &worker_state.runtime.cancel, started, worker_failed, worker_protocol_end.clone()).await;
        if let Err(label) = result {
            let _ = journal.emit("transport_error", json!({"error": label})).await;
            tracing::error!(request_id = %journal.request_id, error = label, "stream delivery failed");
        }
        let completion = if result.is_err() { "incomplete" }
            else if worker_protocol_end.load(Ordering::Acquire) { "protocol_end" }
            else { "http_eof" };
        let recorded = journal.emit("delivery_end", json!({"complete": result.is_ok(), "completion": completion})).await.is_ok();
        finish(&worker_state, &journal, route == "phala" && is_post, receipt.as_deref(), result.is_ok() && recorded).await;
    });
    let mut response = Response::new(Body::from_stream(DeliveryStream {
        inner: ReceiverStream::new(receiver),
        ack: Some(ack),
        failed,
        error_reported: false,
        completion,
        protocol_end,
    }));
    *response.status_mut() = status;
    *response.headers_mut() = response_headers;
    Ok(response)
}

struct Incoming {
    status: StatusCode,
    headers: HeaderMap,
    stream: BoxStream<'static, io::Result<Bytes>>,
}

impl Incoming {
    fn new(response: reqwest::Response, prefix: Vec<Bytes>, read_failed: bool) -> Self {
        let status = response.status();
        let headers = response.headers().clone();
        let rest: BoxStream<'static, io::Result<Bytes>> = if read_failed {
            futures_util::stream::once(async { Err(io::Error::other("upstream read failed")) })
                .boxed()
        } else {
            response
                .bytes_stream()
                .map(|r| r.map_err(|_| io::Error::other("upstream read failed")))
                .boxed()
        };
        let stream = futures_util::stream::iter(prefix.into_iter().map(Ok))
            .chain(rest)
            .boxed();
        Self {
            status,
            headers,
            stream,
        }
    }
}

async fn send_with_session_retry(
    state: &Gateway,
    outgoing: reqwest::RequestBuilder,
    journal: &AsyncJournal,
    enabled: bool,
) -> Result<Incoming, &'static str> {
    for attempt in 0..=2 {
        let mut response = outgoing
            .try_clone()
            .ok_or("NonReplayableRequest")?
            .send()
            .await
            .map_err(|_| "UpstreamConnect")?;
        if !enabled || response.status() != StatusCode::PRECONDITION_FAILED {
            return Ok(Incoming::new(response, Vec::new(), false));
        }
        // Restore every inspected byte when a refusal is ineligible or exhausted.
        // Never replay an inference stream, generic provider error or caller pin.
        let mut prefix = Vec::new();
        let mut body = Vec::new();
        let mut ended = false;
        let mut read_failed = false;
        while body.len() <= 64 * 1024 {
            match response.chunk().await {
                Ok(Some(bytes)) => {
                    body.extend_from_slice(&bytes);
                    prefix.push(bytes);
                }
                Ok(None) => {
                    ended = true;
                    break;
                }
                Err(_) => {
                    read_failed = true;
                    break;
                }
            }
        }
        let refused = ended
            && serde_json::from_slice::<Value>(&body)
                .ok()
                .is_some_and(|v| v["error"]["type"] == "session_not_accepted");
        if !refused || attempt == 2 {
            return Ok(Incoming::new(response, prefix, read_failed));
        }
        journal.emit("upstream_retry", json!({
            "attempt": attempt + 1, "status": 412, "reason": "session_not_accepted",
            "receipt_id": response.headers().get("x-receipt-id").and_then(|v| v.to_str().ok()),
            "body_base64": STANDARD.encode(&body),
        })).await.map_err(|_| "JournalWrite")?;
        tracing::warn!(request_id = %journal.request_id, attempt = attempt + 1, "retrying Phala session refusal");
        tokio::select! {
            _ = state.runtime.cancel.cancelled() => return Err("Shutdown"),
            _ = tokio::time::sleep(Duration::from_millis(if attempt == 0 { 250 } else { 750 })) => {}
        }
    }
    unreachable!()
}

struct DeliveryStream {
    inner: ReceiverStream<io::Result<Bytes>>,
    ack: Option<oneshot::Sender<()>>,
    failed: Arc<AtomicBool>,
    error_reported: bool,
    completion: Option<crate::sse::Completion>,
    protocol_end: Arc<AtomicBool>,
}
impl Stream for DeliveryStream {
    type Item = io::Result<Bytes>;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let next = Pin::new(&mut self.inner).poll_next(cx);
        if let Poll::Ready(Some(Ok(bytes))) = &next
            && self
                .completion
                .as_mut()
                .is_some_and(|observer| observer.feed(bytes))
        {
            self.protocol_end.store(true, Ordering::Release);
        }
        if matches!(next, Poll::Ready(None)) {
            if self.failed.load(Ordering::Acquire) {
                if !self.error_reported {
                    self.error_reported = true;
                    return Poll::Ready(Some(Err(io::Error::other(
                        "Inference stream interrupted",
                    ))));
                }
            } else if let Some(ack) = self.ack.take() {
                let _ = ack.send(());
            }
        }
        next
    }
}

#[allow(clippy::too_many_arguments)]
async fn forward(
    mut stream: BoxStream<'static, io::Result<Bytes>>,
    sender: mpsc::Sender<io::Result<Bytes>>,
    delivered: oneshot::Receiver<()>,
    journal: &AsyncJournal,
    cancel: &CancellationToken,
    started: Instant,
    failed: Arc<AtomicBool>,
    protocol_end: Arc<AtomicBool>,
) -> Result<(), &'static str> {
    let mut drain_deadline = None;
    let mut drained = 0usize;
    let result = async {
        loop {
            let completed = protocol_end.load(Ordering::Acquire);
            if completed && sender.is_closed() && drain_deadline.is_none() {
                drain_deadline = Some(tokio::time::Instant::now() + Duration::from_secs(5));
            }
            let chunk = tokio::select! {
                _ = cancel.cancelled() => return Err("Shutdown"),
                _ = sender.closed(), if drain_deadline.is_none() => {
                    if !protocol_end.load(Ordering::Acquire) { return Err("ClientDisconnected"); }
                    drain_deadline = Some(tokio::time::Instant::now() + Duration::from_secs(5));
                    continue;
                },
                next = async {
                    match drain_deadline {
                        Some(deadline) => tokio::time::timeout_at(deadline, stream.next()).await.map_err(|_| "PostCompletionDrainTimeout"),
                        None => Ok(stream.next().await),
                    }
                } => match next? { Some(Ok(bytes)) => bytes,
                    Some(Err(_)) => return Err("UpstreamRead"), None => break }
            };
            if drain_deadline.is_some() {
                drained = drained.saturating_add(chunk.len());
                if drained > 1024 * 1024 { return Err("PostCompletionDrainLimit"); }
            }
            journal
                .emit(
                    "response_chunk",
                    json!({"body_base64": STANDARD.encode(&chunk)}),
                )
                .await
                .map_err(|_| "JournalWrite")?;
            tokio::select! {
                _ = cancel.cancelled() => return Err("Shutdown"),
                sent = sender.send(Ok(chunk)) => {
                    if sent.is_err() && !protocol_end.load(Ordering::Acquire) {
                        return Err("ClientDisconnected");
                    }
                }
            }
        }
        journal
            .emit(
                "response_end",
                json!({"elapsed_ms": started.elapsed().as_millis()}),
            )
            .await
            .map_err(|_| "JournalWrite")?;
        Ok(())
    }
    .await;
    if let Err(label) = result {
        // A separate terminal flag survives a full channel, making Hyper reset
        // truncated streams even when the client is slow and all slots are used.
        failed.store(true, Ordering::Release);
        return Err(label);
    }
    drop(sender);
    if protocol_end.load(Ordering::Acquire) {
        return Ok(());
    }
    tokio::select! {
        _ = cancel.cancelled() => Err("Shutdown"),
        ack = delivered => if ack.is_ok() || protocol_end.load(Ordering::Acquire) {
            Ok(())
        } else { Err("ClientDisconnected") }
    }
}

fn spawn_finish(
    state: &Arc<Gateway>,
    journal: AsyncJournal,
    audit: bool,
    receipt: Option<String>,
    complete: bool,
) {
    let worker = state.clone();
    state.runtime.tasks.spawn(async move {
        finish(&worker, &journal, audit, receipt.as_deref(), complete).await;
    });
}

async fn finish(
    state: &Gateway,
    journal: &AsyncJournal,
    audit: bool,
    receipt: Option<&str>,
    complete: bool,
) {
    if audit {
        let evidence = tokio::select! {
            _ = state.runtime.cancel.cancelled() => json!({"audit_state": "unavailable", "reason": "gateway stopped before audit completed", "receipt_id": receipt}),
            evidence = audit_result(state, receipt, complete) => evidence,
        };
        if evidence["audit_state"] != "verified" {
            tracing::error!(request_id = %journal.request_id, audit_state = %evidence["audit_state"], "Phala audit did not verify");
        }
        if journal.emit("audit", evidence).await.is_err() {
            tracing::error!(request_id = %journal.request_id, "failed to persist audit; leaving journal open for recovery");
            return;
        }
    }
    if journal.close().await.is_err() {
        tracing::error!(request_id = %journal.request_id, "failed to seal journal");
    }
}

async fn audit_result(state: &Gateway, receipt: Option<&str>, complete: bool) -> Value {
    if !complete {
        return json!({"audit_state": "unavailable", "reason": "response delivery incomplete", "receipt_id": receipt});
    }
    let Some(receipt) = receipt.filter(|r| {
        !r.is_empty()
            && r.len() <= 256
            && r.bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
    }) else {
        return json!({"audit_state": "failed", "reason": "missing or invalid receipt ID"});
    };
    match fetch_audit(state, receipt).await {
        Ok((status, evidence)) => {
            let verdict = &evidence["verdict"];
            let audit_state = if status == StatusCode::OK && verdict["verified"] == true {
                "verified"
            } else if status == StatusCode::OK && verdict["failed"].as_u64().unwrap_or(0) > 0 {
                "failed"
            } else {
                "unavailable"
            };
            json!({"audit_state": audit_state, "receipt_id": receipt, "evidence": evidence})
        }
        Err(label) => json!({"audit_state": "unavailable", "receipt_id": receipt, "error": label}),
    }
}

async fn fetch_audit(state: &Gateway, receipt: &str) -> Result<(StatusCode, Value), &'static str> {
    for attempt in 0..4 {
        let response = state
            .http
            .post(format!(
                "{}/receipts/{receipt}/verify",
                state.config.pap_control
            ))
            .bearer_auth(&state.config.routes["phala"].token)
            .timeout(Duration::from_secs(120))
            .send()
            .await
            .map_err(|_| "ControlRequest")?;
        let status = response.status();
        let mut stream = response.bytes_stream();
        let mut body = Vec::new();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|_| "ControlRead")?;
            if body.len() + chunk.len() > 4 * 1024 * 1024 {
                return Err("OversizedTranscript");
            }
            body.extend_from_slice(&chunk);
        }
        let evidence = serde_json::from_slice(&body).map_err(|_| "InvalidTranscript")?;
        if status != StatusCode::NOT_FOUND || attempt == 3 {
            return Ok((status, evidence));
        }
        tokio::time::sleep(Duration::from_millis(100 * (attempt + 1))).await;
    }
    unreachable!()
}
