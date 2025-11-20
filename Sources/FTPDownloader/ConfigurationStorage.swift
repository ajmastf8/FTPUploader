import Foundation

/// Centralized configuration storage using JSON files in Application Support
/// No keychain access = no password prompts
class ConfigurationStorage {
    static let shared = ConfigurationStorage()

    // Cache to prevent multiple file reads during app startup
    private var cachedConfigurations: [FTPConfig]?
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300.0 // Cache is valid for 5 minutes

    private init() {}

    // MARK: - Load Configurations

    /// Load all configurations from JSON file in Application Support
    /// Uses a short-lived cache to prevent multiple file reads during app startup
    func loadConfigurations() -> [FTPConfig] {
        // Check if we have a valid cache
        if let cached = cachedConfigurations,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            print("✅ Returning \(cached.count) configuration(s) from cache (age: \(String(format: "%.1f", Date().timeIntervalSince(timestamp)))s)")
            return cached
        }

        print("📦 ConfigurationStorage: Loading configurations from JSON...")

        // Load from JSON file
        let jsonConfigs = loadFromJSON()

        if !jsonConfigs.isEmpty {
            print("✅ Loaded \(jsonConfigs.count) configuration(s) from JSON")
        } else {
            print("ℹ️ No configurations found")
        }

        // Update cache
        cachedConfigurations = jsonConfigs
        cacheTimestamp = Date()
        return jsonConfigs
    }

    // MARK: - Save Configuration

    /// Save a single configuration to JSON file
    func saveConfiguration(_ config: FTPConfig) -> Bool {
        print("💾 ConfigurationStorage: Saving configuration '\(config.name)' to JSON...")

        // Load existing configs
        var configs = loadFromJSON()

        // Update or add the configuration
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            print("✏️ Updating existing configuration")
        } else {
            configs.append(config)
            print("➕ Adding new configuration")
        }

        // Save to JSON
        let success = saveToJSON(configs)

        if success {
            print("✅ Configuration saved to JSON")
            // Invalidate cache so next load will fetch fresh data
            cachedConfigurations = nil
            cacheTimestamp = nil
            // Notify MenuBarContentView to reload configurations
            NotificationCenter.default.post(name: NSNotification.Name("ConfigurationsChanged"), object: nil)
        } else {
            print("❌ Failed to save configuration to JSON")
        }

        return success
    }

    // MARK: - Delete Configuration

    /// Delete a configuration from JSON file
    func deleteConfiguration(_ configId: UUID) -> Bool {
        print("🗑️ ConfigurationStorage: Deleting configuration \(configId) from JSON...")

        // Load existing configs
        var configs = loadFromJSON()

        // Remove the configuration
        configs.removeAll { $0.id == configId }

        // Save back to JSON
        let success = saveToJSON(configs)

        if success {
            print("✅ Configuration deleted from JSON")
            // Invalidate cache so next load will fetch fresh data
            cachedConfigurations = nil
            cacheTimestamp = nil
            // Notify MenuBarContentView to reload configurations
            NotificationCenter.default.post(name: NSNotification.Name("ConfigurationsChanged"), object: nil)
        } else {
            print("❌ Failed to delete configuration from JSON")
        }

        return success
    }

    // MARK: - JSON File Operations

    /// Load configurations from JSON file in Application Support
    private func loadFromJSON() -> [FTPConfig] {
        AppFileManager.initialize()
        let configFileURL = AppFileManager.shared.configurationsFileURL

        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            print("📄 No JSON file exists yet at: \(configFileURL.path)")
            return []
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            let configs = try JSONDecoder().decode([FTPConfig].self, from: data)
            print("📄 Loaded \(configs.count) configuration(s) from JSON file: \(configFileURL.path)")
            return configs
        } catch {
            print("❌ Failed to load configurations from JSON: \(error)")
            return []
        }
    }

    /// Save configurations to JSON file in Application Support
    private func saveToJSON(_ configs: [FTPConfig]) -> Bool {
        AppFileManager.initialize()
        let configFileURL = AppFileManager.shared.configurationsFileURL

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configs)
            try data.write(to: configFileURL, options: [.atomic])
            print("✅ Saved \(configs.count) configuration(s) to JSON file: \(configFileURL.path)")
            return true
        } catch {
            print("❌ Failed to save configurations to JSON: \(error)")
            return false
        }
    }

    // MARK: - Export/Import for Backup

    /// Export all configurations to JSON file (for user backup/export)
    func exportToJSON(url: URL) -> Bool {
        let configs = loadFromJSON()

        guard !configs.isEmpty else {
            print("⚠️ No configurations to export")
            return false
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configs)
            try data.write(to: url)
            print("✅ Exported \(configs.count) configuration(s) to: \(url.path)")
            return true
        } catch {
            print("❌ Failed to export configurations: \(error)")
            return false
        }
    }

    /// Import configurations from JSON file (for user restore/import)
    /// Merges with existing configurations (doesn't replace)
    func importFromJSON(url: URL) -> [FTPConfig]? {
        do {
            let data = try Data(contentsOf: url)
            let importedConfigs = try JSONDecoder().decode([FTPConfig].self, from: data)
            print("✅ Imported \(importedConfigs.count) configuration(s) from: \(url.path)")

            // Load existing configs
            var existingConfigs = loadFromJSON()

            // Merge: update existing or add new
            for importedConfig in importedConfigs {
                if let index = existingConfigs.firstIndex(where: { $0.id == importedConfig.id }) {
                    existingConfigs[index] = importedConfig
                    print("  ✏️ Updated existing: \(importedConfig.name)")
                } else {
                    existingConfigs.append(importedConfig)
                    print("  ➕ Added new: \(importedConfig.name)")
                }
            }

            // Save merged configs
            if saveToJSON(existingConfigs) {
                print("✅ Import complete: \(importedConfigs.count) configurations imported and merged")
                // Invalidate cache
                cachedConfigurations = nil
                cacheTimestamp = nil
                return importedConfigs
            } else {
                print("❌ Failed to save imported configurations")
                return nil
            }
        } catch {
            print("❌ Failed to import configurations: \(error)")
            return nil
        }
    }
}
