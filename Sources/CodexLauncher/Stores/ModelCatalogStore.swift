import Foundation
import SwiftUI

@MainActor
final class ModelCatalogStore: ObservableObject {
    @Published var models: [CatalogModel] = []
    @Published var errorMessage: String?

    func ensureModel(slug: String, displayName: String? = nil) {
        let cleanSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSlug.isEmpty else { return }
        guard models.contains(where: { $0.slug == cleanSlug }) == false else { return }

        models.append(CatalogModel(
            slug: cleanSlug,
            displayName: displayName?.isEmpty == false ? displayName! : cleanSlug,
            description: "",
            contextWindow: nil,
            maxContextWindow: nil,
            rawFields: defaultRawFields()
        ))
    }

    func importModels(_ discoveredModels: [DiscoveredModel]) {
        for discovered in discoveredModels {
            ensureModel(slug: discovered.slug, displayName: discovered.displayName)
        }
    }

    func bindingForModel(slug: String) -> Binding<CatalogModel>? {
        let cleanSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSlug.isEmpty,
              models.contains(where: { $0.slug == cleanSlug })
        else { return nil }

        return Binding(
            get: {
                self.models.first(where: { $0.slug == cleanSlug }) ?? CatalogModel(
                    slug: cleanSlug,
                    displayName: cleanSlug,
                    description: "",
                    contextWindow: nil,
                    maxContextWindow: nil
                )
            },
            set: { updatedModel in
                guard let index = self.models.firstIndex(where: { $0.slug == cleanSlug }) else { return }
                self.models[index] = updatedModel
            }
        )
    }

    func load(path: String) {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            models = []
            return
        }

        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            models = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                  let rawModels = dictionary["models"] as? [[String: Any]]
            else {
                models = []
                errorMessage = "JSON 中没有 models 数组。"
                return
            }

            models = rawModels.map {
                CatalogModel(
                    slug: $0["slug"] as? String ?? "",
                    displayName: $0["display_name"] as? String ?? "",
                    description: $0["description"] as? String ?? "",
                    contextWindow: intValue($0["context_window"]),
                    maxContextWindow: intValue($0["max_context_window"]),
                    rawFields: $0
                )
            }
            errorMessage = nil
        } catch {
            models = []
            errorMessage = "读取模型 JSON 失败：\(error.localizedDescription)"
        }
    }

    func save(path: String) {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try backupFile(at: url)
            let payload: [String: Any] = [
                "models": models.map { renderedModel($0) }
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "保存模型 JSON 失败：\(error.localizedDescription)"
        }
    }

    private func renderedModel(_ model: CatalogModel) -> [String: Any] {
        var fields = model.rawFields
        fields["slug"] = model.slug
        fields["display_name"] = model.displayName
        fields["description"] = model.description

        if let contextWindow = model.contextWindow {
            fields["context_window"] = contextWindow
        } else {
            fields.removeValue(forKey: "context_window")
        }

        if let maxContextWindow = model.maxContextWindow {
            fields["max_context_window"] = maxContextWindow
        } else {
            fields.removeValue(forKey: "max_context_window")
        }

        return fields
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func defaultRawFields() -> [String: Any] {
        Self.compatibilityRawFields(baseInstructions: preferredBaseInstructions())
    }

    static func applyCompatibilityPreset(to fields: inout [String: Any]) {
        let baseInstructions = fields["base_instructions"] as? String ?? ""
        let compatibilityFields = compatibilityRawFields(baseInstructions: baseInstructions)
        let fieldsToRemove = [
            "auto_review_model_override",
            "comp_hash",
            "default_service_tier",
            "model_messages"
        ]
        for key in fieldsToRemove {
            fields.removeValue(forKey: key)
        }
        for (key, value) in compatibilityFields {
            fields[key] = value
        }
    }

    static func compatibilityRawFields(baseInstructions: String = "") -> [String: Any] {
        [
            "additional_speed_tiers": [],
            "apply_patch_tool_type": NSNull(),
            "auto_compact_token_limit": NSNull(),
            "availability_nux": NSNull(),
            "base_instructions": baseInstructions,
            "default_reasoning_level": NSNull(),
            "default_reasoning_summary": "auto",
            "default_verbosity": NSNull(),
            "effective_context_window_percent": 95,
            "experimental_supported_tools": [],
            "input_modalities": ["text"],
            "include_skills_usage_instructions": false,
            "multi_agent_version": "disabled",
            "priority": 0,
            "service_tiers": [],
            "shell_type": "default",
            "support_verbosity": false,
            "supported_in_api": true,
            "supported_reasoning_levels": [],
            "supports_image_detail_original": false,
            "supports_parallel_tool_calls": false,
            "supports_reasoning_summary_parameter": false,
            "supports_reasoning_summaries": false,
            "supports_search_tool": false,
            "tool_mode": "direct",
            "truncation_policy": ["limit": 10000, "mode": "bytes"],
            "upgrade": NSNull(),
            "use_responses_lite": false,
            "visibility": "list",
            "web_search_tool_type": "text"
        ]
    }

    private func preferredBaseInstructions() -> String {
        if let instructions = models.first?.rawFields["base_instructions"] as? String,
           !instructions.isEmpty {
            return instructions
        }

        let codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let preferred = [
            "ollama-local-models.json",
            "ollama-pixion-models.json",
            "vllm-pixion-models.json",
            "models_cache.json"
        ]

        for filename in preferred {
            let url = codexHome.appendingPathComponent(filename)
            if let instructions = firstModelBaseInstructions(from: url), !instructions.isEmpty {
                return instructions
            }
        }

        return "You are Codex, a coding agent. Use the tools provided by the client to inspect, edit, and verify the workspace."
    }

    private func firstModelBaseInstructions(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawModels = object["models"] as? [[String: Any]],
              let firstModel = rawModels.first
        else { return nil }

        return firstModel["base_instructions"] as? String
    }

    private func backupFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let now = Date()
        if let lastBackupDate = Self.lastBackupDates[url.path],
           now.timeIntervalSince(lastBackupDate) < Self.backupMinimumInterval {
            return
        }

        let backupDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let timestamp = Self.backupTimestampFormatter.string(from: now)
        var backupURL = backupDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(timestamp).\(url.pathExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: backupURL.path) {
            backupURL = backupDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(timestamp)-\(suffix).\(url.pathExtension)")
            suffix += 1
        }
        try FileManager.default.copyItem(at: url, to: backupURL)
        Self.lastBackupDates[url.path] = now
    }

    private static var lastBackupDates: [String: Date] = [:]
    private static let backupMinimumInterval: TimeInterval = 300

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
