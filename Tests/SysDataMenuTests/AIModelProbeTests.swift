import Foundation
import Testing

@testable import SysDataMenu

/// Downloaded models, one row each. Ollama's layers are shared between
/// models, so the sizes have to add up to what is really on disk rather than
/// count a shared layer once per model.
struct AIModelProbeTests {
    private let gigabyte: Int64 = 1_073_741_824

    private func library(_ models: [(path: String, layers: [(String, Int64)])]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "sysdata-ollama-\(UUID().uuidString)")
        for model in models {
            let file = root.appending(path: "manifests/\(model.path)")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let layers = model.layers.map { "{\"digest\":\"sha256:\($0.0)\",\"size\":\($0.1)}" }.joined(separator: ",")
            try Data("{\"config\":{\"digest\":\"sha256:cfg-\(model.path.hashValue)\",\"size\":1024},\"layers\":[\(layers)]}".utf8).write(to: file)
        }
        return root
    }

    @Test func modelsAreNamedTheWayOllamaNamesThem() {
        #expect(AIModelProbe.ollamaName(components: ["registry.ollama.ai", "library", "llama3", "latest"]) == "llama3:latest")
        #expect(AIModelProbe.ollamaName(components: ["registry.ollama.ai", "someone", "tuned", "q4"]) == "someone/tuned:q4")
        #expect(AIModelProbe.ollamaName(components: ["ghcr.io", "team", "model", "1b"]) == "ghcr.io/team/model:1b")
        #expect(AIModelProbe.ollamaName(components: ["library", "x"]) == nil)
    }

    /// Two tags of one model share their weights. Counting them in both
    /// rows would put the shared gigabytes into the total twice.
    @Test func sharedLayersAreCountedOnceAndNotInEitherModel() throws {
        let root = try library([
            ("registry.ollama.ai/library/llama3/8b", [("weights", 4 * gigabyte), ("a-only", gigabyte)]),
            ("registry.ollama.ai/library/llama3/latest", [("weights", 4 * gigabyte), ("b-only", gigabyte / 2)]),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try #require(AIModelProbe.readOllamaLibrary(root: root))
        let own = Dictionary(uniqueKeysWithValues: result.models.map { ($0.name, $0.ownBytes) })
        #expect(own["llama3:8b"] == gigabyte + 1024)
        #expect(own["llama3:latest"] == gigabyte / 2 + 1024)
        #expect(result.sharedBytes == 4 * gigabyte)
    }

    @Test func removalGoesThroughOllamaWhenItIsInstalled() throws {
        let root = try library([("registry.ollama.ai/library/mistral/latest", [("w", 4 * gigabyte)])])
        defer { try? FileManager.default.removeItem(at: root) }

        let installed = try #require(AIModelProbe.ollamaItems(root: root, ollama: "/opt/homebrew/bin/ollama").first)
        #expect(installed.action.plan == ["/opt/homebrew/bin/ollama rm mistral:latest"])
        #expect(installed.category == .ai)

        let missing = try #require(AIModelProbe.ollamaItems(root: root, ollama: nil).first)
        #expect(missing.action.isManual, "without the tool nothing may delete blobs by hand")
    }

    @Test func smallModelsAreLeftOut() throws {
        let root = try library([("registry.ollama.ai/library/tiny/latest", [("w", 20 * 1_048_576)])])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AIModelProbe.ollamaItems(root: root, ollama: nil).isEmpty)
    }

    @Test func aFolderWithoutManifestsIsNotALibrary() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sysdata-ollama-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AIModelProbe.readOllamaLibrary(root: root) == nil)
    }

    @Test func huggingFaceFolderNamesBecomeRepositories() {
        #expect(AIModelProbe.huggingFaceName(folder: "models--meta-llama--Llama-3.1-8B")?.repository == "meta-llama/Llama-3.1-8B")
        #expect(AIModelProbe.huggingFaceName(folder: "models--gpt2")?.repository == "gpt2")
        #expect(AIModelProbe.huggingFaceName(folder: "datasets--squad")?.kind == "dataset")
        #expect(AIModelProbe.huggingFaceName(folder: ".locks") == nil)
        #expect(AIModelProbe.huggingFaceName(folder: "version.txt") == nil)
    }

    @Test func theHubFollowsTheEnvironmentTheWayHuggingFaceDoes() {
        #expect(AIModelProbe.huggingFaceHub(environment: ["HF_HUB_CACHE": "/data/hub"]).path == "/data/hub")
        #expect(AIModelProbe.huggingFaceHub(environment: ["HF_HOME": "/data/hf"]).path == "/data/hf/hub")
        #expect(AIModelProbe.huggingFaceHub(environment: [:]).path.hasSuffix(".cache/huggingface/hub"))
    }
}
