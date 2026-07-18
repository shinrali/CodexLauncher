# Changelog

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
