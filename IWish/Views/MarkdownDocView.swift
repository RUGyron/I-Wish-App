import SwiftUI

struct MarkdownDocView: View {
    let title: String
    let resourceName: String  // e.g. "privacy", "terms"
    @State private var content: String = "Загрузка..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let attributed = try? AttributedString(
                    markdown: content,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributed)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text(content).font(.body)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadContent() }
    }

    private func loadContent() {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            content = text
        } else {
            content = "Документ временно недоступен. Смотрите на GitHub: https://github.com/RUGyron/I-Wish-App"
        }
    }
}
