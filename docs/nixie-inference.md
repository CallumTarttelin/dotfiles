# Inference on nixie

`hosts/nixie/inference.nix` configures Hermes, a streaming logging gateway,
CLIProxyAPI for OpenAI subscription authentication, and PAP for Phala verification.
The default Phala model is `deepseek/deepseek-v4.1-flash-1017`.
The gateway, journal, Arrow/Parquet exporter, and credential provisioner are Rust
binaries built from `pkgs/inference-gateway`, with dependencies pinned in
`Cargo.lock`. No Python runtime is needed for these services.

## Credentials and first use

The raw Phala key is encrypted in `secrets/phala-api-key.age` with the existing
agenix user and host recipients. It is decrypted only on nixie. Dashboard
authentication is encrypted separately in `secrets/hermes-dashboard.age`.
Internal service credentials are generated on
first start in `/var/lib/inference-credentials`, owned by root.
Private service configuration is generated under `/run/inference`; neither keys
nor OAuth tokens are evaluated into the Nix store.

After deploying the nixie configuration:

```sh
systemctl status inference-credentials inference-gateway phala-verifier cliproxyapi hermes-agent hermes-backend
inference-openai-login
hermes-nixie chat
```

`inference-openai-login` runs CLIProxyAPI's interactive Codex device login as its
service user. OAuth credentials and refreshes persist in
`/var/lib/cliproxyapi/auth`. No OpenAI API key is required for this route. Actual
subscription access, available models and limits depend on the signed-in account.
There are no OAuth credentials until you complete that login.

Hermes has its own user, workspace, memory and sessions under `/var/lib/hermes`.
`hermes-nixie` runs its CLI as that user and shares the service's state. Messaging
platforms are not connected yet. Main and configured auxiliary inference use the
Phala route; the Hermes client token cannot use the OpenAI route.
The model is explicitly configured as a custom OpenAI-compatible endpoint with
`key_env = OPENAI_API_KEY` and the Chat Completions protocol. This binding is
required by the pinned Hermes version: a custom loopback URL alone can resolve
to the `no-key-required` placeholder instead of the generated gateway key,
which causes HTTP 401. Configuration changes apply to new chats; start a new
session if an existing session retained its previous provider settings.

Create a separate gateway API key for each client. On nixie:

```sh
sudo inference-key create --name laptop --route phala
sudo inference-key create --name codex --route openai
sudo inference-key list
sudo inference-key revoke laptop
```

Creation prints `api_key` once; save it in your password manager. Repeat `--route`
to allow both routes. The default route is `phala`. Use that key with the gateway
endpoints below, which forward Phala inference through PAP. Clients never need
the upstream Phala key or an OpenAI refresh token.

Listing shows names, IDs, scopes and creation/revocation dates, without keys or
hashes. Revocation accepts a name or ID and rejects new requests immediately,
without restarting the gateway; an already running request may finish. Rotate by
creating a new named key, updating the client, then revoking its previous key.
Names cannot be reused, including after revocation.

Only key hashes are stored in `/var/lib/inference-client-keys/keys.json`. Root
can edit this registry; the gateway can only read it and reloads it per request.
A missing or invalid registry blocks requests. The registry is not backed up;
create replacement client keys after a fresh restore.

Existing `hermes` and `personal` keys are migrated on the first deployment of the
registry. The Hermes key is Phala-only; the personal key allows both routes.
The `hermes-openai` service key is OpenAI-only and is added when deploying the
OpenAI profile, including to an existing registry. Revoked service keys remain
revoked across rebuilds.
`inference-token` still reads the legacy personal key. Either can be revoked with
`inference-key`; subsequent rebuilds preserve revocations. Revoking `hermes` will
also prevent the managed Hermes service from making inference requests.

## Hermes in the browser

After deploying the dashboard configuration, open
`https://hermes.callumtarttelin.com` while connected to the tailnet.
Sign in as `tarttelin` using the generated password saved in your password manager.
The initial password is handed over privately when configuring the secret;
there is no dashboard-password retrieval command.

The dashboard runs on loopback port 9119 behind Caddy, with its public URL set
explicitly for authentication, assets and WebSockets. Its scrypt password hash
and cookie-signing secret are encrypted in `secrets/hermes-dashboard.age` and
decrypted by agenix for the service, outside the Nix store. The plaintext password
is not stored on nixie. To rotate the login, replace the hash and signing secret
in that encrypted file and rebuild; this also invalidates existing sessions.
The backend shares the Hermes user, configuration and state with `hermes-nixie`.

The DNS-only CNAME `hermes.callumtarttelin.com` points to
`inference.callumtarttelin.com`, whose address is nixie's tailnet IP. The record
was created in Cloudflare; this Nix module does not manage DNS records. Caddy uses
the existing wildcard certificate and permits tailnet source addresses only.

Use its sessions/chat views for Hermes conversations and its usage views for
Hermes activity. It does not include Codex requests made directly to the inference
gateway. The gateway API bases below remain separate from the dashboard.

## Private and OpenAI profiles

Use the profile selector in the same Hermes dashboard to choose **default**
(private / Phala) or **openai** (GPT-6.1 Sol through the subscription gateway).
Start a new conversation in the intended profile instead of changing the model
of a private conversation. On nixie, the equivalent CLI commands are:

```sh
hermes-nixie chat
hermes-nixie -p openai chat
```

The default profile keeps all existing memories, user notes, sessions and
workspace. The new `openai` profile is created from scratch under
`/var/lib/hermes/.hermes/profiles/openai`, with its own memories, user notes,
session database and workspace. Nothing is cloned from the private profile.
Rebuilds manage its configuration, credential and policy while retaining new
memories, chats and work. If an unmanaged `openai` profile already exists, setup
refuses to overwrite it; rename that profile before deploying this configuration.

Gmail is available in the default profile. The OpenAI profile has no seeded Gmail
skills and is instructed to use only its own memory/workspace and explicitly
shared sources. The agent's `gws` executable rejects use from named profiles.
This is an aid against accidental sharing, **not an OS security boundary**:
both profiles run as the same user, and deliberate shell/file access can bypass
the convention. Sharing memory requires explicitly choosing what to copy; there
is no automatic cross-profile recall or shared memory pool. Existing history is
private by default. Avoid cross-profile session searches or attaching private
session links to an OpenAI chat.

Each profile's generated gateway key allows only its own route, and neither
profile has provider fallback configured. Summarization, compression and the
other configured auxiliary model calls follow that profile's main provider.
The OpenAI profile uses a named custom provider so the pinned Hermes version
retains Responses API mode on the loopback gateway URL. No raw OAuth credential
is copied into either profile.

To connect the OpenAI subscription, run the interactive device login:

```sh
ssh -t nixie inference-openai-login
```

Complete the printed browser flow. Then select `openai` and send a short message
to check actual access to `gpt-6.1-sol`; a model catalog alone does not establish
account entitlement. The profile is configured before login but cannot infer
until authentication is complete and the account has access. OAuth state is not
backed up. The shared inference archive still records both routes with client
labels `hermes` and `hermes-openai`; neither profile can read the archive under
normal file permissions.

## Google Workspace / Gmail

`gws` is installed from the nixpkgs revision pinned in `flake.lock`, so it updates
with the normal nixpkgs update. It is on the PATH of both Hermes services and
`hermes-nixie`. The declarative `gws-gmail` skill explains searching and reading
mail through the terminal tool. No separate Gmail MCP server is needed.
The skill loads automatically. The bundled `google-workspace` skill is disabled:
its scripts require `HERMES_HOME/google_token.json` and force that path into
`GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE`, bypassing the credentials imported for
gws. Hermes should invoke `gws` directly rather than running those setup/API
scripts. The agent's gws executable pins its config directory independently of
the terminal's `HOME`; changing HOME does not require moving credentials.

For manual checks, `sudo -u hermes -H gws ...` runs the CLI as the Hermes user,
using `/var/lib/hermes/.config/gws` (mode 0700). The agent uses the file keyring
backend, which works without a desktop keyring. OAuth state is not backed up or
stored in Nix; authenticate again after a fresh restore. Google authorization is separate from
the Phala and Hermes dashboard credentials.

For a headless nixie, authorize on your desktop and transfer the refresh
credentials using the upstream [headless export workflow](https://github.com/googleworkspace/cli#headless--ci-export-flow):

1. In a Google Cloud project, enable the Gmail API, configure the OAuth consent
   screen, and create a **Desktop app** OAuth client. Add your Google account as a
   test user if the app is in testing mode. Download its client JSON.
2. From this repository on your desktop, enter the pinned CLI environment:

   ```sh
   nix shell .#nixosConfigurations.nixie.pkgs.gws
   ```

3. Create a separate local configuration for the Hermes authorization:

   ```sh
   umask 077
   export GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-hermes"
   mkdir -p "$GOOGLE_WORKSPACE_CLI_CONFIG_DIR"
   chmod 700 "$GOOGLE_WORKSPACE_CLI_CONFIG_DIR"
   ```

   Save the downloaded client JSON as
   `~/.config/gws-hermes/client_secret.json`. Then run:

   ```sh
   gws auth login --scopes https://www.googleapis.com/auth/gmail.readonly
   gws auth export --unmasked > gws-hermes-credentials.json
   scp gws-hermes-credentials.json nixie:
   ```

   Complete consent in your desktop browser. This grants Gmail read-only access
   plus Google's identity scopes; it does not grant sending or modifying mail.
4. On nixie, install the exported credentials for Hermes and remove the transfer
   file:

   ```sh
   sudo install -o hermes -g hermes -m 0600 \
     ~/gws-hermes-credentials.json /var/lib/hermes/.config/gws/credentials.json
   rm ~/gws-hermes-credentials.json
   sudo -u hermes -H gws auth status
   sudo -u hermes -H gws gmail users messages list \
     --params '{"userId":"me","q":"in:inbox","maxResults":5}'
   ```

   Delete the desktop `gws-hermes-credentials.json` export too. These JSON files
   contain refresh credentials; do not commit them or paste them into a chat.

Start a new Hermes chat and ask it to use the `gws-gmail` skill to summarize
recent inbox messages. No service restart is needed after importing Google
credentials. The email content Hermes reads may become part of the inference
prompts and therefore the existing inference archive and its backups.

## Client endpoints

The local API bases are:

* Phala: `http://127.0.0.1:8090/phala/v1`
* OpenAI subscription: `http://127.0.0.1:8090/openai/v1`

Caddy exposes the same paths at `https://inference.callumtarttelin.com`, accepting
tailnet sources only and flushing streams immediately. DNS for that name must
resolve to nixie's Tailscale address on your clients; this module does not create
the DNS record. PAP's data/control ports and CLIProxyAPI remain loopback-only.

For Codex, merge providers/profiles into your **user-level** `~/.codex/config.toml`:

```toml
[model_providers.nixie-phala]
name = "Phala through nixie"
base_url = "https://inference.callumtarttelin.com/phala/v1"
env_key = "NIXIE_INFERENCE_TOKEN"
wire_api = "responses"
supports_websockets = false
capabilities = { remote_compaction = "unsupported" }

[model_providers.nixie-openai]
name = "OpenAI subscription through nixie"
base_url = "https://inference.callumtarttelin.com/openai/v1"
env_key = "NIXIE_INFERENCE_TOKEN"
wire_api = "responses"
supports_websockets = false
capabilities = { remote_compaction = "unsupported" }

[profiles.nixie-phala]
model_provider = "nixie-phala"
model = "deepseek/deepseek-v4.1-flash-1017"

[profiles.nixie-openai]
model_provider = "nixie-openai"
# Set model to an ID returned by the OpenAI route's GET /models after login.
```

Supply `NIXIE_INFERENCE_TOKEN` from your secret manager. Start with
`codex --profile nixie-phala` or `codex --profile nixie-openai`. This does not
rewrite existing client configurations or intercept clients that use other
providers. WebSockets, remote compaction endpoints, uploads, and backend
management APIs are not exposed; use HTTP Responses/SSE. For custom clients,
available inference paths are `chat/completions`, `responses`, `messages`,
`embeddings` and `models` (upstream support still varies).

## Verification and routing

Phala requests go exclusively to PAP, which verifies the upstream channel before
forwarding and requires an attested serving session (`--require-claim tee_attested`).
An unavailable verifier or invalid preflight blocks the Phala route. Nothing
falls back from Phala to OpenAI. The Phala route also allows only the configured
default model; change `model` in the host module to select another model.

Startup audits the current serving sessions before binding the local API, which
can take several minutes. Look for PAP's JSON `ready` event; an active systemd
process alone does not mean the listener is ready. During startup, Phala calls
receive an upstream-unavailable error. The OpenAI route remains independent.

Responses stream immediately. Once a response finishes, the gateway asks PAP's
local control endpoint to audit its receipt against PAP's captured wire digests.
It records the returned transcript under the same request ID. PAP's ordinary
audit also runs, so the control call may perform a second audit. The control call
retries briefly when the exchange has not yet entered PAP's in-memory ring.

Streaming clients may stop at a protocol terminal event (`[DONE]`, Responses
completion/failure/incomplete, or Anthropic `message_stop`) instead of consuming
HTTP EOF. The gateway recognizes complete SSE events across chunk boundaries
once its HTTP response consumer has consumed the terminal event. If that client
then closes, the gateway drains and records the remaining upstream bytes for at
most five seconds and 1 MiB. It still requires a clean upstream EOF and PAP's
receipt verification before marking the exchange verified. A marker alone never
passes an audit. Early client disconnects, upstream truncation and drain limits
remain unavailable. `delivery_end` records completion as `protocol_end`,
`http_eof` or `incomplete`; this is transport/protocol accounting, not proof that
a human read the response.

PAP already refreshes policy-derived session pins after a 412 refusal. If a
Phala POST still returns a complete JSON error with type `session_not_accepted`,
the gateway allows two additional attempts after 250 ms and 750 ms. Each attempt
goes through PAP's existing verification and pin refresh. These explicit
refusals occur before inference is forwarded; other errors and started streams
are never replayed. Requests supplying their own `provider.aci_session_ids` and
all OpenAI requests are excluded. Persistent refusal reaches the caller as 412.
Each discarded refusal is retained as an `upstream_retry` journal event with its
body, receipt ID and attempt number; the final exchange gets the normal audit.

Audit states are `pending`, `verified`, `failed`, `unavailable`, or
`not_applicable`. Missing receipts fail; network errors, interrupted delivery,
shutdowns and incomplete evidence remain unavailable. A failure is persisted and
logged at error level without retracting already delivered output. Observe them:

```sh
journalctl -u inference-gateway -p err
journalctl -u phala-verifier
```

The gateway emits systemd priority prefixes without ANSI formatting, so new
errors appear under `-p err` and JSON journal readers get text messages. Older
gateway entries were logged at journald's default priority despite saying ERROR;
use the full `journalctl -u inference-gateway` when reviewing those historical
entries. The completion fix does not relabel historical unavailable audits.

The baseline relies on PAP's vendor-root verification and serving claim checks.
It does not pin a reviewed gateway compose hash, KMS root, or production OS
measurement. Add explicit PAP policy flags if you want those additional trust
anchors. Updating the client package never automatically approves a new workload
measurement. OpenAI subscription requests have no Phala attestation.

## Inspecting verification and usage

PAP is running in standalone `serve` mode. Its recent receipt list is an in-memory
ring of up to 256 exchanges, with verification states, not a durable token or
billing dashboard. On nixie:

```sh
curl -fsS http://127.0.0.1:4183/receipts
journalctl -fu phala-verifier
journalctl -u inference-gateway -p err
```

`verified: null` means an audit is pending or could not complete; `true` means it
passed, and `false` means it failed. A response can appear before its audit. PAP
also logs `request_complete` for the post-delivery audit; count receipt IDs rather
than log lines to avoid double-counting its automatic and explicit audits.

This pinned CLIProxyAPI release no longer ships built-in usage statistics. Its
management panel is intentionally disabled, and no separate CPA analytics service
is installed. Complete `inference-openai-login` to make OpenAI models available.
The gateway archive is the durable source for traffic across both providers.

For recent completed requests before the overnight export, on nixie run
`sudo -u inference-gateway duckdb`, then:

```sql
CREATE VIEW events AS
SELECT * FROM read_json_auto(
  '/var/lib/inference-gateway/journal/*.jsonl',
  format = 'newline_delimited'
);

SELECT route, json_extract_string(data_json, '$.model') AS model,
       count(*) AS requests
FROM events
WHERE kind = 'request'
  AND json_extract_string(data_json, '$.model') IS NOT NULL
GROUP BY ALL;

SELECT json_extract_string(data_json, '$.audit_state') AS audit_state,
       count(*) AS requests
FROM events
WHERE kind = 'audit'
GROUP BY ALL;
```

This recent-data query requires at least one sealed `.jsonl` file. It excludes
still-running `.open` journals. After export, use the Parquet view below instead;
the files are exported rather than copied, so querying only journals does not
include historical traffic. Token usage is retained when the upstream response
includes it; subscription quotas and provider billing are not calculated here.

## Journal, Parquet and DuckDB

Each request gets an append-only journal in
`/var/lib/inference-gateway/journal`. The gateway fsyncs the request before sending
it upstream, records streamed bytes as ordered base64 chunks, and appends the
final audit transcript. It excludes authentication headers and does not log
arbitrary client headers. Response bodies still contain whatever the model
returns. These files contain private conversation data.

The archive records the client-facing inference exchange and the PAP audit
transcript, not CLIProxyAPI's internal OAuth refresh traffic, translated requests,
account-selection decisions, or PAP's rewritten request body. Token counts and
tool calls are retained in the raw response/SSE payloads; there is no separate
cost calculation or dashboard. Agent files and tool operations outside inference
are excluded from the archive and from this stack's backups.

An unclean shutdown preserves complete journal events, drops a torn final line,
and marks the exchange as recovered/incomplete. Only closed journals are exported.
Live requests and audits cannot be picked up by the exporter.

At **00:30 Europe/London**, the export timer combines completed journals into
Zstd-compressed Parquet batches partitioned by the request's UTC start date.
Adjust `OnCalendar` to the actual Economy 7 meter window, including any GMT/BST
rules. `Persistent=false` prevents a missed overnight job from running at daytime
boot. The timer exports closed journals into a batch per day represented in that
run; it does not continually rewrite existing Parquet files. At this volume,
one nightly batch per day is normally sufficient.

Batch staging, fsync, atomic publication, and cleanup allow retries without
duplicating a published batch. A lock serializes manual/timer exports. Run one:

```sh
sudo systemctl start inference-archive
sudo -u inference-gateway duckdb
```

In DuckDB:

```sql
CREATE VIEW events AS
SELECT * FROM read_parquet(
  '/var/lib/inference-gateway/parquet/**/*.parquet',
  union_by_name = true
);

SELECT timestamp, request_id, route,
       json_extract_string(data_json, '$.audit_state') AS audit_state
FROM events
WHERE kind IN ('audit', 'recovered')
ORDER BY timestamp DESC;
```

The event envelope has `schema_version`, `event_id`, `request_id`, `sequence`,
`timestamp`, `route`, `client`, `kind`, and `data_json`. Raw request/response bytes
are base64 in `data_json.body_base64`; concatenate decoded `response_chunk`
payloads in sequence order to reconstruct a response. Do not decode individual
chunks as UTF-8 before joining them: character boundaries can cross chunks.

The Rust service retains the original version-1 JSONL and Parquet schema. Existing
Python-written journals, interrupted export batches, and Parquet files need no
conversion. The service commands and generated JSON configuration also retain
their previous interfaces.

For this stack, both existing nixie restic jobs include only the inference data:
journals, in-progress export batches, and Parquet, with their audit metadata.
Hermes runtime state, OAuth credentials and generated client credentials are not
backed up. After a restore, Nix recreates configuration, the provisioner generates
new gateway tokens, clients need those new tokens, and OpenAI requires a fresh
interactive login. The Phala key remains managed separately by agenix.
Export and backups share a filesystem lock so moving a batch cannot race the
backup walk. No automatic retention deletion is configured.

## Updates and checks

`nix run .#pre-update` updates the CLIProxyAPI/PAP release URLs and hashes in
`pkgs/inference-tools/pins.json`, plus the Hermes release tag in `flake.nix`.
The existing workflow's following `nix flake update` refreshes the Hermes lock.
To update just these components locally:

```sh
nix run .#pre-update -- inference
nix flake update hermes-agent
```

The updater downloads and hashes all binary assets before changing pins. Missing
assets or unexpected release tags stop the update. Gateway tests run during its
Nix build and cover streaming before audit, failed/missing receipts, authentication
and route restrictions, exact captured bytes, torn journal recovery, and a crash
between Parquet publication and source cleanup.
They also cover SDK-style closes at terminal events, truncated/held-open tails,
bounded session-refusal retries, non-replay of caller pins/OpenAI requests, and
journal severity prefixes.
