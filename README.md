# CodexLauncher

CodexLauncher is a small macOS SwiftUI launcher for managing local Codex model
profiles and model providers. It edits the relevant files under `~/.codex`,
stores provider tokens in macOS Keychain, and launches `/Applications/Codex.app`
with the selected profile materialized as Codex's active model configuration.

It is intended for people who switch between multiple Codex model backends, such
as OpenAI-compatible proxies, local Ollama, LM Studio, vLLM, or other custom
providers.

## Requirements

- macOS 14 or later
- `/Applications/Codex.app`
- Swift toolchain / Xcode command line tools, if building from source
- Codex CLI bundled inside the app:

```sh
/Applications/Codex.app/Contents/Resources/codex
```

## Download

Download the latest app bundle zip from GitHub Releases:

[CodexLauncher releases](https://github.com/shinrali/CodexLauncher/releases)

After downloading, unzip `CodexLauncher-vX.Y.Z.zip` and run
`CodexLauncher.app`.

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
swift build -c release
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
  the selected profile's active top-level model keys before launching Codex.app.
- macOS Keychain
  Stores provider tokens by provider id.

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
`/Applications/Codex.app`:

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

The Official entry launches `/Applications/Codex.app` without selecting a
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
  Optional environment variable name used by Codex for the bearer token. If a
  Keychain token exists and `env_key` is blank, CodexLauncher generates one from
  the provider id, such as `OMLX_API_KEY` for `oMLX`.
- `wire_api`
  Currently normalized to `responses`.
- `token`
  Stored in macOS Keychain, not in `config.toml`.

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

If you enter a token in CodexLauncher, the token is stored in Keychain and
injected through `env_key` when launching Codex. Fetch Models can use the
Keychain token directly from the app.

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
3. Fill `base_url`, `env_key`, and optional token.
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

Token lookup order:

1. Token stored in CodexLauncher's Keychain entry for that provider.
2. The configured `env_key` from the current process environment.
3. The configured `env_key` from the user's login shell environment.

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

## Token Handling

Provider tokens are not written to the repository or to `config.toml`.

They are stored in macOS Keychain with this service name:

```text
CodexLauncher.ProviderToken
```

The provider id is used as the Keychain account name.

## Local Files Created

Running the app may create or update:

```text
~/.codex/config.toml
~/.codex/codex-launcher-state.json
~/.codex/<profile>.config.toml
~/.codex/<provider>-models.json
~/.codex/backups/config-*.toml
```

Backups are created before writing `~/.codex/config.toml`.

## Release Packaging

Build a release binary:

```sh
swift build -c release
```

Create or update the app bundle:

```sh
mkdir -p dist/CodexLauncher.app/Contents/MacOS dist/CodexLauncher.app/Contents/Resources
cp .build/release/CodexLauncher dist/CodexLauncher.app/Contents/MacOS/CodexLauncher
cp Resources/AppIcon.icns dist/CodexLauncher.app/Contents/Resources/AppIcon.icns
```

Zip the app for GitHub Releases:

```sh
ditto --noextattr --norsrc -c -k --keepParent dist/CodexLauncher.app dist/CodexLauncher-v0.1.2.zip
```

`dist/` is intentionally ignored by Git. Upload the zip file as a GitHub Release
asset instead of committing it to the repository.

## Notes

- This app assumes Codex is installed at `/Applications/Codex.app`.
- Custom provider ids cannot be the reserved Codex provider ids `openai`,
  `ollama`, or `lmstudio`.
- `base_url` values are normalized on save. For example, `localhost:8888`
  becomes `http://localhost:8888/v1`.
- `wire_api` is normalized to `responses`.
- The app is currently unsigned and unnotarized.

## License

MIT License. See [LICENSE](LICENSE).
