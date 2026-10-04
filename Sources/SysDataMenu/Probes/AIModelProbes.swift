import Foundation

// MARK: - Downloaded models, one row each

/// Ollama and Hugging Face keep every model in one folder, so the old rows
/// said "Ollama models: 41 GB" and offered to delete all of it. The one-model
/// question people actually have — which of these did I stop using — needs a
/// row per model, and for Ollama a delete that goes through `ollama rm`,
/// because its layers are shared and removing blobs by hand corrupts the rest.
struct AIModelProbe: StorageProbe {
    private static let threshold = 100 * ProbeSupport.megabyte

    func probe() async -> [StorageItem] {
        let environment = ProcessInfo.processInfo.environment
        let ollamaRoot = environment["OLLAMA_MODELS"].map { URL(fileURLWithPath: $0) } ?? .home(".ollama/models")
        let hubRoot = Self.huggingFaceHub(environment: environment)

        var items = Self.ollamaItems(root: ollamaRoot, ollama: Shell.which("ollama"))
        items += await Self.huggingFaceItems(hub: hubRoot)
        items += await Self.aggregateIfUnreadable(items: items, ollamaRoot: ollamaRoot)
        return items.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
    }

    // MARK: Ollama

    struct OllamaModel: Equatable {
        /// The name `ollama pull` and `ollama rm` take: `llama3:latest`,
        /// `someone/model:tag`, or with the registry when it is not Ollama's.
        let name: String
        /// Bytes that go when this model goes: layers no other model uses.
        let ownBytes: Int64
        let modified: Date?
    }

    struct OllamaLibrary: Equatable {
        let models: [OllamaModel]
        /// Layers two or more models use, counted once. They are freed when
        /// the last of those models is removed.
        let sharedBytes: Int64
    }

    private struct Manifest: Decodable {
        struct Layer: Decodable {
            let digest: String
            let size: Int64
        }
        let config: Layer?
        let layers: [Layer]?
    }

    /// Reads `manifests/<registry>/<namespace>/<model>/<tag>` and sizes each
    /// model from its own manifest, without touching the weights.
    static func readOllamaLibrary(root: URL) -> OllamaLibrary? {
        let manifests = root.appending(path: "manifests")
        guard let walker = FileManager.default.enumerator(
            at: manifests, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else { return nil }

        var parsed: [(name: String, layers: [Manifest.Layer], modified: Date?)] = []
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let data = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  let name = ollamaName(components: relativeComponents(of: file, in: manifests))
            else { continue }
            parsed.append((name, (manifest.config.map { [$0] } ?? []) + (manifest.layers ?? []), values?.contentModificationDate))
        }
        guard !parsed.isEmpty else { return nil }

        var users: [String: Int] = [:]
        var sizes: [String: Int64] = [:]
        for model in parsed {
            for layer in Set(model.layers.map(\.digest)) { users[layer, default: 0] += 1 }
            for layer in model.layers { sizes[layer.digest] = layer.size }
        }
        let models = parsed.map { model in
            OllamaModel(
                name: model.name,
                ownBytes: Set(model.layers.map(\.digest)).filter { users[$0] == 1 }.reduce(0) { $0 + (sizes[$1] ?? 0) },
                modified: model.modified
            )
        }
        let shared = users.filter { $0.value > 1 }.keys.reduce(0) { $0 + (sizes[$1] ?? 0) }
        return OllamaLibrary(models: models.sorted { $0.name < $1.name }, sharedBytes: shared)
    }

    private static func relativeComponents(of file: URL, in base: URL) -> [String] {
        let prefix = base.standardizedFileURL.pathComponents
        return Array(file.standardizedFileURL.pathComponents.dropFirst(prefix.count))
    }

    static func ollamaName(components: [String]) -> String? {
        guard components.count >= 4 else { return nil }
        let tag = components[components.count - 1]
        let model = components[components.count - 2]
        let namespace = components[components.count - 3]
        let registry = components.dropLast(3).joined(separator: "/")
        if registry == "registry.ollama.ai" {
            return namespace == "library" ? "\(model):\(tag)" : "\(namespace)/\(model):\(tag)"
        }
        return "\(registry)/\(namespace)/\(model):\(tag)"
    }

    static func ollamaItems(root: URL, ollama: String?) -> [StorageItem] {
        guard let library = readOllamaLibrary(root: root) else { return [] }
        var items: [StorageItem] = library.models.compactMap { model in
            guard model.ownBytes >= threshold else { return nil }
            return StorageItem(
                id: "ai-ollama-\(model.name)", category: .ai, name: "Ollama: \(model.name)",
                detail: ollama == nil
                    ? "Run `ollama rm \(model.name)`. `ollama pull \(model.name)` fetches it again."
                    : "Removed with `ollama rm`, which needs Ollama running. `ollama pull \(model.name)` fetches it again.",
                sizeBytes: model.ownBytes, safety: ollama == nil ? .manual : .review,
                action: ollama.map { .command(executable: $0, arguments: ["rm", model.name]) }
                    ?? .manual("ollama rm \(model.name)"),
                revealURL: root, lastModified: model.modified
            )
        }
        if library.sharedBytes >= threshold {
            items.append(StorageItem(
                id: "ai-ollama-shared", category: .ai, name: "Ollama: layers shared by several models",
                detail: "Freed on their own when the last model that uses them is removed.",
                sizeBytes: library.sharedBytes, safety: .manual,
                action: .manual("Remove the models that use these layers with `ollama rm`."),
                revealURL: root
            ))
        }
        return items
    }

    // MARK: Hugging Face

    static func huggingFaceHub(environment: [String: String]) -> URL {
        if let hub = environment["HF_HUB_CACHE"] { return URL(fileURLWithPath: hub) }
        if let home = environment["HF_HOME"] { return URL(fileURLWithPath: home).appending(path: "hub") }
        return .home(".cache/huggingface/hub")
    }

    /// `models--meta-llama--Llama-3` is the repository `meta-llama/Llama-3`;
    /// `datasets--` and `spaces--` are kept apart from models by their prefix.
    static func huggingFaceName(folder: String) -> (kind: String, repository: String)? {
        for kind in ["models", "datasets", "spaces"] where folder.hasPrefix("\(kind)--") {
            let repository = folder.dropFirst(kind.count + 2).replacingOccurrences(of: "--", with: "/")
            guard !repository.isEmpty else { return nil }
            return (String(kind.dropLast()), repository)
        }
        return nil
    }

    static func huggingFaceItems(hub: URL) async -> [StorageItem] {
        var items: [StorageItem] = []
        for folder in hub.children(includeHidden: false) where folder.isDirectory {
            guard let name = huggingFaceName(folder: folder.lastPathComponent),
                  let item = await ProbeSupport.directoryItem(
                    id: "ai-hf-\(folder.lastPathComponent)", category: .ai,
                    name: "Hugging Face \(name.kind): \(name.repository)",
                    detail: "Downloaded from Hugging Face. It is fetched again the next time a program asks for it.",
                    url: folder, safety: .review, action: .removePaths([folder]), minimumBytes: threshold
                  )
            else { continue }
            items.append(item)
        }
        let xet = hub.deletingLastPathComponent().appending(path: "xet")
        if let item = await ProbeSupport.directoryItem(
            id: "ai-hf-xet", category: .ai, name: "Hugging Face download chunks",
            detail: "Chunks kept to speed up downloads. Fetched again when needed.",
            url: xet, safety: .review, action: .removePaths([xet]), minimumBytes: threshold
        ) {
            items.append(item)
        }
        return items
    }

    // MARK: Fallback

    /// The folders used to be one row each. If a layout this probe does not
    /// understand left a large folder with no rows at all, the whole folder is
    /// reported again, so a change in either tool never hides gigabytes.
    private static func aggregateIfUnreadable(items: [StorageItem], ollamaRoot: URL) async -> [StorageItem] {
        var extra: [StorageItem] = []
        if !items.contains(where: { $0.id.hasPrefix("ai-ollama") }),
           let item = await ProbeSupport.directoryItem(
            id: "tool-.ollama/models", category: .ai, name: "Ollama models",
            detail: "Downloaded LLM weights. `ollama pull` fetches them again.",
            url: ollamaRoot, safety: .review, action: .removePaths([ollamaRoot]), minimumBytes: 10 * ProbeSupport.megabyte
           ) {
            extra.append(item)
        }
        let huggingFace = URL.home(".cache/huggingface")
        if !items.contains(where: { $0.id.hasPrefix("ai-hf") }),
           let item = await ProbeSupport.directoryItem(
            id: "tool-.cache/huggingface", category: .ai, name: "Hugging Face cache",
            detail: "Downloaded models and datasets.",
            url: huggingFace, safety: .review, action: .removePaths([huggingFace]), minimumBytes: 10 * ProbeSupport.megabyte
           ) {
            extra.append(item)
        }
        return extra
    }
}
