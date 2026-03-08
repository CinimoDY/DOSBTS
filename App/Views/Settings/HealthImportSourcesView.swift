//
//  HealthImportSourcesView.swift
//  DOSBTS
//

import HealthKit
import SwiftUI

struct HealthImportSourcesView: View {
    @EnvironmentObject var store: DirectStore
    @State private var availableSources: [String] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading sources...")
                        .foregroundColor(AmberTheme.amberDark)
                }
            } else if availableSources.isEmpty {
                Text("No source apps found in Apple Health.")
                    .foregroundColor(AmberTheme.amberDark)
            } else {
                Section(
                    content: {
                        ForEach(availableSources, id: \.self) { source in
                            Toggle(source, isOn: sourceBinding(for: source))
                                .toggleStyle(SwitchToggleStyle(tint: AmberTheme.amber))
                        }
                    },
                    header: {
                        Text("Toggle which apps to import from")
                    }
                )
            }
        }
        .navigationTitle("Source Apps")
        .onAppear {
            loadSources()
        }
    }

    private func sourceBinding(for source: String) -> Binding<Bool> {
        Binding(
            get: {
                !store.state.healthImportExcludedSources.contains(source)
            },
            set: { enabled in
                var excluded = store.state.healthImportExcludedSources
                if enabled {
                    excluded.removeAll { $0 == source }
                } else {
                    excluded.append(source)
                }
                store.dispatch(.setHealthImportExcludedSources(excludedSources: excluded))
            }
        )
    }

    private func loadSources() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isLoading = false
            return
        }

        let healthStore = HKHealthStore()
        let carbType = HKQuantityType(.dietaryCarbohydrates)
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""

        let query = HKSourceQuery(sampleType: carbType, samplePredicate: nil) { _, sources, _ in
            let names = (sources ?? [])
                .filter { $0.bundleIdentifier != ownBundleID }
                .map { $0.name }
                .sorted()

            DispatchQueue.main.async {
                self.availableSources = names
                self.isLoading = false
            }
        }
        healthStore.execute(query)
    }
}
