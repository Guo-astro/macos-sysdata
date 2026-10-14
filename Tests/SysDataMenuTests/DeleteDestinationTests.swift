import Foundation
import Testing

@testable import SysDataMenu

/// Where Review items go is chosen in the confirmation. The default keeps the
/// Trash as the undo; "Delete now" deletes outright and says nothing about
/// the Trash afterwards, because there is nothing in it to empty.
@MainActor
struct DeleteDestinationTests {
    private func reviewItem(at url: URL) -> StorageItem {
        StorageItem(
            id: "review-\(url.lastPathComponent)", category: .tools, name: url.lastPathComponent, detail: "",
            sizeBytes: 10, safety: .review, action: .removePaths([url])
        )
    }

    @Test func deleteNowRemovesAReviewItemWithoutTouchingTheTrash() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sysdata-delete-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "file"))
        let item = reviewItem(at: folder)
        let model = ScanModel(scansAutomatically: false, items: [item])
        let before = model.deletesReviewItemsImmediately
        model.deletesReviewItemsImmediately = true
        defer { model.deletesReviewItemsImmediately = before }

        await model.reclaim(item)

        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(!model.noticeOffersEmptyingTheTrash)
        #expect(model.notice == nil || !(model.notice ?? "").contains("Trash"))
    }

    @Test func theChoiceIsRememberedAndOffByDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "deletesReviewItemsImmediately")
        defer {
            if let saved { defaults.set(saved, forKey: "deletesReviewItemsImmediately") }
            else { defaults.removeObject(forKey: "deletesReviewItemsImmediately") }
        }
        defaults.removeObject(forKey: "deletesReviewItemsImmediately")
        #expect(ScanModel(scansAutomatically: false, items: []).deletesReviewItemsImmediately == false)

        let model = ScanModel(scansAutomatically: false, items: [])
        model.deletesReviewItemsImmediately = true
        #expect(ScanModel(scansAutomatically: false, items: []).deletesReviewItemsImmediately == true)
    }
}
