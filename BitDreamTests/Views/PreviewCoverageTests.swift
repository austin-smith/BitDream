import Foundation
import XCTest

#if DEBUG
final class PreviewCoverageTests: XCTestCase {
    func testEverySwiftUIViewFileHasAColocatedPreview() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            repositoryRoot.appending(path: "BitDream"),
            repositoryRoot.appending(path: "BitDreamWidgets")
        ]
        let viewPattern = try NSRegularExpression(
            pattern: #"(?m)^\s*(?:(?:private|internal|public)\s+)?struct\s+\w+(?:<[^>]+>)?\s*:\s*View\b"#
        )
        var missingPreviews: [String] = []

        for sourceRoot in sourceRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else {
                XCTFail("Unable to enumerate \(sourceRoot.path)")
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                guard !fileURL.path.contains("/PreviewSupport/") else { continue }
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let sourceRange = NSRange(source.startIndex..., in: source)
                guard viewPattern.firstMatch(in: source, range: sourceRange) != nil else { continue }
                guard !source.contains("#Preview"), !source.contains("PreviewProvider") else { continue }

                missingPreviews.append(
                    fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                )
            }
        }

        XCTAssertTrue(
            missingPreviews.isEmpty,
            "SwiftUI view files without a colocated preview:\n\(missingPreviews.sorted().joined(separator: "\n"))"
        )
    }
}
#endif
