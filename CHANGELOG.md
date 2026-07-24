# Changelog

## v0.1.6 - 2026-07-24

- Generate new local model catalog entries with direct-tool compatibility defaults instead of copying capabilities from unrelated local catalogs or `models_cache.json`.
- Add Model Catalog controls for tool mode, shell type, apply-patch type, multi-agent version, parallel calls, search, Responses Lite, modalities, and truncation mode.
- Add a one-click compatibility reset that explicitly selects `tool_mode = "direct"` and `apply_patch_tool_type = null`.

## v0.1.5 - 2026-07-21

- Deliver locally stored provider tokens through Codex command authentication instead of relying on ChatGPT.app to inherit launch environment variables.
- Install a private token helper under Application Support and automatically migrate existing `env_key` providers that already have a locally stored token.
- Separate provider authentication into Local Token, Environment, and Command modes.
- Distribute releases as a drag-to-Applications DMG.

## v0.1.4 - 2026-07-18

- Show the current version in the macOS About window and bundle metadata.
- Add command-backed bearer token authentication for custom model providers.
- Preserve unknown provider keys and nested provider tables when editing or renaming providers.
- Support provider query parameters, static headers, environment-backed headers, and command authentication when fetching `/models`.
- Keep `auth.json` reserved for OpenAI/ChatGPT login credentials; third-party static tokens use CodexLauncher's private local JSON and are injected through `env_key`.
- Replace Keychain-backed provider tokens with a private `provider-secrets.json` file under Application Support to avoid repeated macOS password prompts.

## v0.1.3 - 2026-07-12

- Launch the renamed `/Applications/ChatGPT.app`, while retaining compatibility with the legacy `/Applications/Codex.app`.
- Keep model provider display names independent from the selected model; provider names continue to come only from each provider's own `name` (or its id when blank).

## v0.1.2 - 2026-07-07

- Fix a crash when switching a profile between providers after editing provider settings.
- Make model catalog editor bindings resilient when the selected provider reloads a different model JSON.
- Generate a default provider `env_key` from the provider id when a Keychain token exists and `env_key` is blank.
- Clarify provider token and `env_key` behavior in the README.

## v0.1.1 - 2026-06-18

- Stop automatically renaming model providers when saving profiles or reloading config.
- Show provider display names in the profile `model_provider` picker, with the provider id kept as secondary context when different.
- Update release packaging docs for the `v0.1.1` zip asset.

## v0.1.0 - 2026-06-16

- Initial public release of CodexLauncher.
