//
//  AboutView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - AboutView

struct AboutView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        Section {
            Text("DOSBTS is a community-maintained reader app that displays data from Libre sensors. It is **not a medical device**. Treatment decisions must be verified with your CGM manufacturer's reader and your healthcare provider.")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amber)
        } header: {
            Label("Disclaimer", systemImage: "exclamationmark.shield")
        }

        // Permanent What's New history (DMNC-1147, R8): full build changelog,
        // openable anytime. Pushed into the settings NavigationStack — entries
        // render plain here (linksActive: false, R12). Parsed once in .task
        // (not in the destination closure, which SwiftUI rebuilds on every
        // store publish — DMNC-1147 review).
        Section {
            NavigationLink {
                WhatsNewView(builds: changelogBuilds, linksActive: false)
            } label: {
                Label("What's New", systemImage: "sparkles")
            }
            .task {
                if changelogBuilds.isEmpty { changelogBuilds = ChangelogParser.bundled() }
            }
        } header: {
            Label("Changelog", systemImage: "list.bullet.rectangle")
        }

        Section(
            content: {
                HStack {
                    Text("App version")
                    Spacer()
                    Text(verbatim: "\(DirectConfig.appVersion) (\(DirectConfig.appBuild))")
                }

                if let buildDate = DirectConfig.appBuildDate {
                    HStack {
                        Text("Build date")
                        Spacer()
                        Text(verbatim: Self.buildDateFormatter.string(from: buildDate))
                            .monospacedDigit()
                    }
                }

                HStack {
                    Text("Forked from")
                    Spacer()
                    Link("GlucoseDirect", destination: DirectConfig.upstreamGlucoseDirectURL)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                if let appAuthor = DirectConfig.appAuthor, !appAuthor.isEmpty {
                    HStack {
                        Text("App author")
                        Spacer()
                        Text(verbatim: appAuthor)
                    }
                }

                if let appSupportMail = DirectConfig.appSupportMail,
                   !appSupportMail.isEmpty,
                   let mailURL = URL(string: "mailto:\(appSupportMail)") {
                    HStack {
                        Text("App email")
                        Spacer()
                        Link(appSupportMail, destination: mailURL)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }

                HStack {
                    Text("App website")
                    Spacer()
                    Link("GitHub", destination: DirectConfig.githubURL)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                HStack {
                    Text("App faq")
                    Spacer()
                    Link("GitHub", destination: DirectConfig.faqURL)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                HStack {
                    Text(verbatim: "Support upstream GlucoseDirect")
                    Spacer()
                    Link("PayPal", destination: DirectConfig.upstreamDonateURL)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                HStack {
                    Text(verbatim: "Tip the DOSBTS fork")
                    Spacer()
                    Link("Sponsors", destination: DirectConfig.sponsorURL)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            },
            header: {
                Label("About \(DirectConfig.appName)", systemImage: "info")
            }
        )
        
        Section(
            content: {
                Button("Export as CSV", action: {
                    store.dispatch(.exportToUnknown)
                })
                
                Button("Export for Tidepool", action: {
                    store.dispatch(.exportToTidepool)
                })
                
                Button("Export for Glooko", action: {
                    store.dispatch(.exportToGlooko)
                })
            },
            header: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        )
        
        Button("Send database file", action: {
            store.dispatch(.sendDatabase)
        })

        Button("Send log file", action: {
            store.dispatch(.sendLogs)
        })

        if DirectConfig.isDebug {
            Section(
                content: {
                    Button("Debug alarm", action: {
                        store.dispatch(.debugAlarm)
                    })
                    
                    Button("Debug notification", action: {
                        store.dispatch(.debugNotification)
                    })
                },
                header: {
                    Label("Debug", systemImage: "testtube.2")
                }
            )
        }
    }

    // MARK: Private

    @State private var showingDeleteLogsAlert = false
    @State private var changelogBuilds: [ChangelogBuild] = []

    private static let buildDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
