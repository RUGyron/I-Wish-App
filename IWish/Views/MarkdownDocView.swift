import SwiftUI

struct MarkdownDocView: View {
    let title: String
    let resourceName: String
    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    block.view
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            blocks = [.paragraph("Документ недоступен")]
            return
        }
        blocks = parseMarkdown(text)
    }
}

// MARK: - Markdown Block

enum MarkdownBlock {
    case h1(String), h2(String), h3(String)
    case paragraph(String)
    case bullet(String)
    case hr
    case table([String], [[String]])

    @ViewBuilder var view: some View {
        switch self {
        case .h1(let text):
            Text(text).font(.largeTitle.weight(.bold)).padding(.top, 8)
        case .h2(let text):
            Text(text).font(.title2.weight(.semibold)).padding(.top, 8)
        case .h3(let text):
            Text(text).font(.headline.weight(.semibold)).padding(.top, 4)
        case .paragraph(let text):
            if let attr = try? AttributedString(markdown: text) {
                Text(attr).font(.body)
            } else {
                Text(text).font(.body)
            }
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\u{2022}").foregroundStyle(.secondary)
                if let attr = try? AttributedString(markdown: text) {
                    Text(attr).font(.body)
                } else {
                    Text(text).font(.body)
                }
            }
        case .hr:
            Divider().padding(.vertical, 8)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ForEach(headers, id: \.self) { h in
                        Text(h).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        ForEach(row, id: \.self) { cell in
                            Text(cell).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Parser

func parseMarkdown(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = text.components(separatedBy: "\n")
    var paragraphBuffer: [String] = []
    var inTable = false
    var tableHeaders: [String] = []
    var tableRows: [[String]] = []

    func flushParagraph() {
        if !paragraphBuffer.isEmpty {
            blocks.append(.paragraph(paragraphBuffer.joined(separator: " ")))
            paragraphBuffer.removeAll()
        }
    }

    func flushTable() {
        if inTable {
            blocks.append(.table(tableHeaders, tableRows))
            tableHeaders.removeAll()
            tableRows.removeAll()
            inTable = false
        }
    }

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("# ") {
            flushParagraph(); flushTable()
            blocks.append(.h1(String(trimmed.dropFirst(2))))
        } else if trimmed.hasPrefix("## ") {
            flushParagraph(); flushTable()
            blocks.append(.h2(String(trimmed.dropFirst(3))))
        } else if trimmed.hasPrefix("### ") {
            flushParagraph(); flushTable()
            blocks.append(.h3(String(trimmed.dropFirst(4))))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            flushParagraph(); flushTable()
            blocks.append(.bullet(String(trimmed.dropFirst(2))))
        } else if trimmed == "---" || trimmed == "***" {
            flushParagraph(); flushTable()
            blocks.append(.hr)
        } else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
            flushParagraph()
            let cells = trimmed.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if !inTable {
                tableHeaders = cells
                inTable = true
            } else if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) {
                // separator row, skip
            } else {
                tableRows.append(cells)
            }
        } else if trimmed.isEmpty {
            flushParagraph(); flushTable()
        } else {
            if inTable { flushTable() }
            paragraphBuffer.append(trimmed)
        }
    }
    flushParagraph(); flushTable()
    return blocks
}
