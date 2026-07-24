# CodexLauncher

CodexLauncher is a small macOS SwiftUI launcher for managing local Codex model
profiles and model providers. It edits the relevant files under `~/.codex`,
stores provider tokens in its private Application Support JSON file, and launches `/Applications/ChatGPT.app`
with the selected profile materialized as Codex's active model configuration.

It is intended for people who switch between multiple Codex model backends, such
as OpenAI-compatible proxies, local Ollama, LM Studio, vLLM, or other custom
providers.

## Requirements

- macOS 14 or later
- `/Applications/ChatGPT.app` (the current app; legacy `/Applications/Codex.app` is also supported)
- Swift toolchain / Xcode command line tools, if building from source
- Codex CLI bundled inside the app:

```sh
/Applications/ChatGPT.app/Contents/Resources/codex
```

## Download

Download the latest DMG from GitHub Releases:

[CodexLauncher releases](https://github.com/shinrali/CodexLauncher/releases)

After downloading, open `CodexLauncher-vX.Y.Z.dmg`, then drag
`CodexLauncher.app` onto the `Applications` folder shortcut.

Because this app is not notarized yet, macOS may block the first launch. If that
happens, open System Settings -> Privacy & Security and allow the app, or
right-click the app and choose Open.

## Build From Source

Clone the repository:

```sh
git clone git@github.com:shinrali/CodexLauncher.git
cd CodexLauncher
```

Build and run the app:

```sh
./script/build_and_run.sh --verify
```

The script builds the Swift package, creates `dist/CodexLauncher.app`, and opens
the app.

For a release-style binary:

```sh
./script/build_and_run.sh --release
```

## What The App Edits

CodexLauncher keeps launcher-managed profile presets separate from Codex's base
configuration:

- `~/.codex/codex-launcher-state.json`
  Stores the launcher profile list.
- `~/.codex/<profile>.config.toml`
  Stores Codex 0.134.0+ profile-layer files using top-level config keys.
- `~/.codex/config.toml`
  Preserves existing config, writes `[model_providers.*]` entries, and writes
  the selected profile's active top-level model keys before launching ChatGPT.app.
- `~/Library/Application Support/CodexLauncher/provider-secrets.json`
  Stores provider tokens by provider id with file permissions set to `600`.

Other sections in `~/.codex/config.toml` are preserved.

## Codex Profile Model

Codex 0.134.0 and later no longer reads legacy `[profiles.name]` tables from
`~/.codex/config.toml`. A named profile is now a separate file:

```toml
# ~/.codex/example.config.toml
model = "gpt-5.5"
model_provider = "openai"
model_catalog_json = "/Users/me/.codex/example-models.json"
```

CodexLauncher follows that layout by writing the matching
`~/.codex/<profile>.config.toml`.

For the desktop app, CodexLauncher also writes the selected profile into the
active top-level keys in `~/.codex/config.toml` before launching
`/Applications/ChatGPT.app`:

```toml
model = "gpt-5.5"
model_provider = "openai"
model_catalog_json = "/Users/me/.codex/example-models.json"
```

This compatibility step is required because the desktop app starts from the
active config file and does not directly pick a separate profile file.
CodexLauncher backs up `~/.codex/config.toml` before changing it and preserves
non-launcher-managed sections.

## Main Concepts

### Official

The Official entry launches `/Applications/ChatGPT.app` without selecting a
launcher profile. It also clears launcher-managed top-level active model keys
from `~/.codex/config.toml`.

Use this when you want Codex to behave like the normal installed app.

### Model Providers

A model provider describes how Codex connects to a backend:

- `id`
  The provider id used by `model_provider`.
- `name`
  Human-readable provider name.
- `base_url`
  OpenAI-compatible API base URL, such as `http://localhost:11434/v1`.
- `env_key`
  Environment variable name used only when the provider authentication mode is
  explicitly set to Environment.
- `wire_api`
  Currently normalized to `responses`.
- `token`
  Stored in CodexLauncher's private Application Support JSON, not in `config.toml`.

Provider settings that CodexLauncher does not edit, including `query_params`,
`http_headers`, `env_http_headers`, and future nested provider tables, are
preserved when the provider is saved or renamed.

Example provider in `~/.codex/config.toml`:

```toml
[model_providers.local-ollama]
name = "Local Ollama"
base_url = "http://127.0.0.1:11434/v1"
wire_api = "responses"
```

For an authenticated provider:

```toml
[model_providers.proxy]
name = "OpenAI-compatible proxy"
base_url = "https://proxy.example.com/v1"
env_key = "PROXY_API_KEY"
wire_api = "responses"
```

If you select Local Token in CodexLauncher, the token is stored in its private
local JSON file. The launcher installs a private helper under Application
Support and writes official command-backed authentication into `config.toml`:

```toml
[model_providers.proxy.auth]
command = "/Users/me/Library/Application Support/CodexLauncher/bin/CodexLauncherTokenHelper"
args = ["--print-provider-token", "proxy"]
timeout_ms = 5000
refresh_interval_ms = 0
```

Codex invokes this helper when it needs the bearer token. This works even when
ChatGPT.app does not inherit environment variables from the launcher. Existing
providers with a locally stored token and `env_key` are migrated automatically.

For short-lived bearer tokens, Codex also supports command-backed
authentication:

```toml
[model_providers.proxy]
name = "Proxy"
base_url = "https://proxy.example.com/v1"
wire_api = "responses"

[model_providers.proxy.auth]
command = "/usr/local/bin/fetch-codex-token"
args = ["--audience", "codex"]
timeout_ms = 5000
refresh_interval_ms = 300000
```

The command must print only the bearer token to stdout. User-supplied Command
authentication cannot be combined with `env_key`, a locally stored token,
`experimental_bearer_token`, or `requires_openai_auth`.

### Profiles

A profile links a model to a provider:

- `Profile name`
  The launcher profile id and Codex profile filename prefix.
- `model`
  The exact model slug to use.
- `model_provider`
  One of the configured provider ids.
- `model_catalog_json`
  Generated automatically from the provider id.
- `openai_base_url`
  Optional override for the built-in OpenAI provider. Custom providers usually
  do not need this.

Example generated profile file:

```toml
model = "qwen3.6:35b-a3b"
model_provider = "local-ollama"
model_catalog_json = "/Users/me/.codex/local-ollama-models.json"
```

## Typical Workflow

1. Open CodexLauncher.
2. Add or select a Model Provider.
3. Fill `base_url`, select Local Token, and enter the provider token.
4. Click Save Provider.
5. Add or select a Profile.
6. Choose the provider in `model_provider`.
7. Enter or fetch a model slug.
8. Click Save.
9. Click Run Codex.

If Codex is already running, CodexLauncher asks before closing and relaunching
it with the selected profile.

## Fetch Models

The Profile editor can fetch model names from the selected provider's `/models`
endpoint.

Authentication lookup order:

1. A user-supplied authentication command, when Command mode is selected.
2. Token stored in CodexLauncher's private Application Support JSON for that provider.
3. The configured `env_key` from the current process or login shell environment.

Fetched models are saved into the provider's model catalog JSON file under
`~/.codex`.

## Model Catalog JSON

CodexLauncher writes provider-specific model catalog files such as:

```text
~/.codex/local-ollama-models.json
~/.codex/proxy-models.json
```

These files let Codex show and resolve local/custom model metadata. The Model
Catalog tab lets you inspect and edit the current profile's model metadata.

New local model entries use conservative tool compatibility settings:

- `tool_mode = "direct"`
- `shell_type = "default"`
- `apply_patch_tool_type = null`
- `multi_agent_version = "disabled"`
- `supports_parallel_tool_calls = false`
- `supports_search_tool = false`
- `use_responses_lite = false`

The Model Catalog editor exposes these protocol-sensitive fields as menus and
toggles. Code Mode, freeform apply-patch, parallel calls, search, and Responses
Lite should only be enabled when the custom provider and model are known to
support their corresponding request and tool formats. Restore Compatible
Defaults resets these fields without replacing the model's base instructions.

## Token Handling

Provider tokens are not written to the repository or to `config.toml`.
They are also not written to `~/.codex/auth.json`; that file belongs to
OpenAI/ChatGPT login credential storage.

They are stored in:

```text
~/Library/Application Support/CodexLauncher/provider-secrets.json
```

The containing directory is set to mode `700` and the JSON file to mode `600`.
The managed token helper and its `bin` directory are set to mode `700`. The
helper prints only the requested provider token to Codex over stdout. Existing
legacy Keychain entries are not read, migrated, or deleted automatically.

## Local Files Created

Running the app may create or update:

```text
~/.codex/config.toml
~/.codex/codex-launcher-state.json
~/.codex/<profile>.config.toml
~/.codex/<provider>-models.json
~/Library/Application Support/CodexLauncher/provider-secrets.json
~/Library/Application Support/CodexLauncher/bin/CodexLauncherTokenHelper
~/.codex/backups/config-*.toml
```

Backups are created before writing `~/.codex/config.toml`.

## Release Packaging

Build the signed app and drag-to-Applications DMG:

```sh
./script/package_release.sh
```

The current app version is read from `VERSION` and written to
`CFBundleShortVersionString` and `CFBundleVersion`, so it appears in the macOS
About window and Finder metadata.

The script creates `dist/CodexLauncher-vX.Y.Z.dmg`. Opening the image shows the
app alongside an `Applications` shortcut for drag-and-drop installation.

`dist/` is intentionally ignored by Git. Upload the DMG as a GitHub Release
asset instead of committing it to the repository.

## Notes

- This app prefers the current `/Applications/ChatGPT.app` and falls back to the legacy `/Applications/Codex.app`.
- Custom provider ids cannot be the reserved Codex provider ids `openai`,
  `ollama`, or `lmstudio`.
- `base_url` values are normalized on save. For example, `localhost:8888`
  becomes `http://localhost:8888/v1`.
- `wire_api` is normalized to `responses`.
- The local build uses an ad-hoc signature and is not notarized.

## License

MIT License. See [LICENSE](LICENSE).
