import SwiftUI
import AlarmyCore

/// The barcodes that can be used for a barcode mission, on the Objects tab.
struct BarcodesSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var adding = false
    @State private var pendingDelete: RegisteredBarcode?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Barcodes")
                .font(Theme.display(26))
                .foregroundColor(Theme.moon)
                .padding(.top, 32)
            Text("Pick something you keep away from your bed, like the toothpaste in the bathroom.")
                .font(Theme.caption)
                .foregroundColor(Theme.dusk)
                .padding(.vertical, 8)

            ForEach(model.state.barcodes) { barcode in
                HStack(spacing: 12) {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundColor(Theme.sunlight)
                        .accessibilityHidden(true)
                    Text(barcode.name)
                        .font(Theme.bodyStrong)
                        .foregroundColor(Theme.moon)
                    Spacer()
                    if !model.isLocked {
                        Button { pendingDelete = barcode } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 34, height: 34)
                                .foregroundColor(Theme.moon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(barcode.name)")
                    }
                }
                .padding(12)
                .background(Theme.nightSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 8)
            }

            if let message {
                Text(message).font(Theme.caption).foregroundColor(Theme.siren).padding(.bottom, 8)
            }

            PrimaryButton(title: "Add barcode", background: Theme.nightSurface, foreground: Theme.moon) {
                adding = true
            }
            .padding(.top, 8)
            .disabled(model.isLocked)
            .opacity(model.isLocked ? 0.4 : 1)
        }
        .fullScreenCover(isPresented: $adding) {
            AddBarcodeView().environmentObject(model)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "barcode")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let barcode = pendingDelete {
                    message = model.deleteBarcode(barcode.id)
                        ? nil
                        : (model.isLocked ? "Barcodes can't be changed right now." : "An alarm that's on is using this barcode.")
                }
                pendingDelete = nil
            }
        }
    }
}

struct AddBarcodeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = BarcodeScanner()
    @State private var code: String?
    @State private var name = ""
    @State private var error: String?

    private var canSave: Bool {
        code != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "New barcode") {
                Button("Cancel") { dismiss() }.foregroundColor(Theme.dusk)
            }

            if scanner.authorization == .denied || scanner.authorization == .restricted {
                CameraAccessOff(message: "Camera access is off. Turn it on to scan a barcode.")
                    .foregroundColor(Theme.moon)
            } else {
                CameraPreview(session: scanner.session)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius, style: .continuous))
            }

            Text(code.map { "Found \($0)" } ?? "Point the camera at a barcode or QR code.")
                .font(Theme.bodyStrong)
                .foregroundColor(code == nil ? Theme.dusk : Theme.sunlight)
                .lineLimit(2)

            TextField("", text: $name, prompt: Text("Name, like Toothpaste").foregroundColor(Theme.dusk))
                .font(Theme.body)
                .foregroundColor(Theme.moon)
                .padding(14)
                .background(Theme.nightSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("barcode-name")

            if let error {
                Text(error).font(Theme.caption).foregroundColor(Theme.siren)
            }

            Spacer(minLength: 0)

            PrimaryButton(title: "Save barcode") { save() }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 16)
        .background(Theme.night.ignoresSafeArea())
        .onAppear { scanner.onScan = found }
        .task { await scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private func found(_ scanned: String) {
        if let existing = model.state.barcodes.first(where: { $0.code == scanned }) {
            error = "You've already added this one as \(existing.name)."
        } else {
            error = nil
            code = scanned
            Haptics.success()
        }
    }

    private func save() {
        guard let code else { return }
        if model.addBarcode(name: name.trimmingCharacters(in: .whitespaces), code: code) {
            dismiss()
        } else {
            error = "Barcodes can't be changed right now."
        }
    }
}
