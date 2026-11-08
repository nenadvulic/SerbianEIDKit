//
//  ContentView.swift
//  EidReaderDemo
//
//  Minimal UI demonstrating SerbianEIDKit: connect a CCID reader, insert the card,
//  tap "Read card". Requires the com.apple.security.smartcard entitlement.
//

import SwiftUI
import UIKit
import SerbianEIDKit

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var document: EidDocument?
    @Published var photo: UIImage?
    @Published var status = "Ready. Connect the reader and insert the card."
    @Published var isLoading = false
    @Published var logs: [String] = []

    func read() {
        isLoading = true
        status = "Reading…"
        document = nil
        photo = nil
        logs = []
        Task {
            do {
                let reader = try await SerbianEIDReader()
                reader.onLog = { [weak self] line in
                    Task { @MainActor in self?.logs.append(line) }
                }
                let document = try await reader.readAll()
                let jpeg = try? await reader.readPhoto()
                self.document = document
                if let jpeg, let image = UIImage(data: jpeg) { self.photo = image }
                self.status = "Read successfully."
            } catch {
                self.status = "Error: \(error)"
                self.logs.append("‼︎ \(error)")
            }
            self.isLoading = false
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ReaderViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(action: model.read) {
                        Label(model.isLoading ? "Reading…" : "Read card",
                              systemImage: "person.text.rectangle")
                    }
                    .disabled(model.isLoading)
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let photo = model.photo {
                    Section("Photo") {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                    }
                }

                if let document = model.document {
                    Section("Identity") {
                        row("Full name", document.fullName)
                        row("JMBG", document[.personalNumber])
                        row("Sex", document[.sex])
                        row("Date of birth", document.dateOfBirthFormatted)
                        row("Place of birth", document.fullPlaceOfBirth)
                    }
                    Section("Document") {
                        row("Type", document[.documentType])
                        row("Number", document[.documentRegNumber])
                        row("Serial", document[.documentSerialNumber])
                        row("Issued", EidDocument.formatDate(document[.issuingDate]))
                        row("Expires", EidDocument.formatDate(document[.expiryDate]))
                        row("Authority", document[.issuingAuthority])
                    }
                    Section("Address") {
                        row("Street", "\(document[.street]) \(document[.houseNumber])\(document[.houseLetter])")
                        row("Place", document[.place])
                        row("Community", document[.community])
                        row("State", document[.state])
                    }
                }

                if !model.logs.isEmpty {
                    Section("APDU log") {
                        ScrollView {
                            Text(model.logs.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }
            .navigationTitle("SerbianEIDKit")
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

#Preview { ContentView() }
