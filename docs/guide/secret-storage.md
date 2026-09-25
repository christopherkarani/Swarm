# Secret Storage

API keys, auth headers, and checkpointed conversation content are secrets.
Swarm keeps them out of persisted configuration, log output, and
group-readable files:

- **Store keys in the Keychain.** ``SecretReference`` points at a secret held
  in a ``SecretStore``; configurations persist the pointer, and the raw key is
  resolved only when a request is built.
- **Redact by default.** Configuration debug descriptions and public trace
  logs render secrets as `[redacted]`.
- **Restrict files.** Checkpoints, memory stores, and cached web artifacts are
  written owner-only (`0600` files; store-created directories are `0700`).

## Secret references

``OpenAICompatibleProviderConfiguration``, ``WebSearchTool/Configuration``,
and ``HTTPMCPServer`` accept either an inline key or an
``apiKeyReference``. The inline key wins when non-empty; otherwise the
reference is resolved from the store you pass alongside:

```swift
import Swarm

let reference = SecretReference(service: "com.example.app", account: "openai-api-key")

let store: any SecretStore
#if canImport(Security)
let keychain = KeychainSecretStore()
if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
    try await keychain.save(key, for: reference)
}
store = keychain
#else
store = EnvironmentSecretStore()
#endif

let configuration = OpenAICompatibleProviderConfiguration(
    baseURL: URL(string: "https://api.openai.com/v1")!,
    apiKeyReference: reference,
    model: "gpt-4o"
)

let provider: OpenAICompatibleProvider = .openAICompatible(configuration, secretStore: store)
```

The same shape works for web search and MCP:

```swift
let web = WebSearchTool(
    configuration: WebSearchTool.Configuration(apiKeyReference: reference),
    secretStore: store
)

let mcp = try HTTPMCPServer(
    url: URL(string: "https://mcp.example.com/api")!,
    name: "example",
    apiKeyReference: reference,
    secretStore: store
)
```

## Stores

| Store | Backend | Writes | Use it when |
|---|---|---|---|
| ``KeychainSecretStore`` | OS Keychain generic-password items (Apple only) | Yes | Production apps on Apple platforms |
| ``EnvironmentSecretStore`` | Process environment, keyed by `reference.account` | No (read-only) | Linux, CI, containers |
| ``InMemorySecretStore`` | Process memory | Yes | Tests and previews |

`KeychainSecretStore` writes with `whenUnlockedThisDeviceOnly` protection and
no iCloud sync by default; pass another ``KeychainAccessible`` value to change
the class. `EnvironmentSecretStore` reads the variable named by
`reference.account` and ignores `service`, so one reference shape works on
every platform. `SecretStoreError` describes failures without ever containing
the secret value.

## Redaction

`String(reflecting:)` on ``OpenAICompatibleProviderConfiguration``,
``WebSearchTool/Configuration``, ``WebSearchTool``, and
`OTLPHTTPExporterConfiguration` renders API keys as `[redacted]` and redacts
sensitive header values (`Authorization`, `api-key`, `Cookie`, …) while
keeping benign ones (`Content-Type`, `api-version`) readable. Use
``SecretRedaction/redactedSensitiveValues(_:)`` and
``SecretRedaction/redactingKnownSecrets(in:secrets:)`` for your own log
payloads.

Public trace logs (``ConsoleTracer``, ``SwiftLogTracer``, ``OSLogTracer``)
additionally redact metadata keys that carry credentials — `api_key`,
`authorization`, `token`, `session_id`, `password`, `client_secret`, and
compounds such as `access_token` — while leaving count telemetry like
`tokenUsage` untouched.

## Checkpoint and memory file permissions

File-system workflow checkpoints, ContextCore checkpoints, Wax memory stores,
and the web memory plane are written with owner-only permissions: files are
always `0600`, and directories created by the store are `0700`, plus the
`completeUntilFirstUserAuthentication` Data Protection class where the
platform enforces it. Pre-existing directories keep their permissions (the
store never chmods directories it does not own). No code changes are needed
for new writes.

**Migrating existing directories.** Files written before this hardening keep
their original permissions. Migrate a workflow checkpoint directory in place:

```swift
let hardened = try WorkflowCheckpointing.hardenFilePermissions(in: checkpointsURL)
print("hardened \(hardened) items")
```

For other stores (ContextCore checkpoints, Wax, web memory plane), either
delete and re-run so files are recreated hardened, or run
`chmod -R go-rwx <directory>` once.
