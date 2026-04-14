import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings {
        settingsList.first ?? AppSettings.loadOrCreate(in: context)
    }

    var body: some View {
        Form {
            Section("Внешний вид") {
                Picker("Тема", selection: themeBinding) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
            Section("Желания") {
                Picker("Валюта по умолчанию", selection: currencyBinding) {
                    Text("Рубль (RUB)").tag("RUB")
                    Text("Доллар (USD)").tag("USD")
                }
            }
        }
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    private var themeBinding: Binding<ThemeMode> {
        Binding(
            get: { settings.themeMode },
            set: {
                settings.themeMode = $0
                try? context.save()
            }
        )
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { settings.defaultCurrency },
            set: {
                settings.defaultCurrency = $0
                try? context.save()
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .modelContainer(for: [Wishlist.self, Item.self, AppSettings.self], inMemory: true)
    }
}
