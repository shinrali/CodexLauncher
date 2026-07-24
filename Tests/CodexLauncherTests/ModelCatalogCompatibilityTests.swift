import Foundation
import Testing
@testable import CodexLauncher

@MainActor
struct ModelCatalogCompatibilityTests {
    @Test func newModelsUseDirectCompatibilityMetadata() {
        let store = ModelCatalogStore()

        store.ensureModel(slug: "local-model")

        let fields = store.models[0].rawFields
        #expect(fields["tool_mode"] as? String == "direct")
        #expect(fields["shell_type"] as? String == "default")
        #expect(fields["supports_parallel_tool_calls"] as? Bool == false)
        #expect(fields["supports_search_tool"] as? Bool == false)
        #expect(fields["use_responses_lite"] as? Bool == false)
        #expect(fields["multi_agent_version"] as? String == "disabled")
        #expect(fields["apply_patch_tool_type"] is NSNull)
        #expect(fields["input_modalities"] as? [String] == ["text"])
    }

    @Test func compatibilityPresetRemovesHostedModelMetadata() {
        var fields: [String: Any] = [
            "base_instructions": "Keep this prompt",
            "tool_mode": "code_mode_only",
            "use_responses_lite": true,
            "supports_parallel_tool_calls": true,
            "supports_search_tool": true,
            "apply_patch_tool_type": "freeform",
            "multi_agent_version": "v2",
            "comp_hash": "server-owned",
            "model_messages": ["instructions_template": "server-owned"]
        ]

        ModelCatalogStore.applyCompatibilityPreset(to: &fields)

        #expect(fields["base_instructions"] as? String == "Keep this prompt")
        #expect(fields["tool_mode"] as? String == "direct")
        #expect(fields["use_responses_lite"] as? Bool == false)
        #expect(fields["supports_parallel_tool_calls"] as? Bool == false)
        #expect(fields["supports_search_tool"] as? Bool == false)
        #expect(fields["multi_agent_version"] as? String == "disabled")
        #expect(fields["apply_patch_tool_type"] is NSNull)
        #expect(fields["comp_hash"] == nil)
        #expect(fields["model_messages"] == nil)
    }

    @Test func catalogRoundTripPreservesCapabilitySelections() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let catalogURL = directory.appendingPathComponent("models.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ModelCatalogStore()
        store.ensureModel(slug: "local-model")
        store.models[0].rawFields["tool_mode"] = "code_mode"
        store.models[0].rawFields["apply_patch_tool_type"] = "freeform"
        store.models[0].rawFields["supports_parallel_tool_calls"] = true
        store.save(path: catalogURL.path)

        let reloaded = ModelCatalogStore()
        reloaded.load(path: catalogURL.path)

        #expect(reloaded.models[0].rawFields["tool_mode"] as? String == "code_mode")
        #expect(reloaded.models[0].rawFields["apply_patch_tool_type"] as? String == "freeform")
        #expect(reloaded.models[0].rawFields["supports_parallel_tool_calls"] as? Bool == true)
    }
}
