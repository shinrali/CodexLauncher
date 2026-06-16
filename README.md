# CodexLauncher

macOS SwiftUI app for editing Codex profile presets and model providers, then launching `/Applications/Codex.app` with the selected profile passed as one-off `codex app -c ...` overrides.

## Run

```sh
./script/build_and_run.sh --verify
```

The app source lives in `Sources/CodexLauncher/`.

## What It Edits

- `~/.codex/codex-launcher-state.json` for launcher-managed profile presets
- `~/.codex/<profile>.config.toml` files for Codex 0.134.0+ profile layers
- `[model_providers.*]` in `~/.codex/config.toml`
- one-off launch overrides for `model`, `openai_base_url`, `model_provider`, and `model_catalog_json`

Other sections in `config.toml` are preserved.
