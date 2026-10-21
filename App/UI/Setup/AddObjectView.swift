import SwiftUI
import AlarmyCore

struct AddObjectView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController(torchOn: false)
    @State private var name = ""
    @State private var shots: [UIImage] = []
    @State private var error: String?
    @State private var busy = false
    @State private var lookalike: RegisteredObject?

    private let maxShots = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "Add object") {
                Button("Cancel") { dismiss() }.foregroundColor(Theme.dusk)
            }

            if camera.authorization == .denied || camera.authorization == .restricted {
                CameraAccessOff(message: "Camera access is off. Turn it on to photograph your objects.")
            } else {
                ZStack(alignment: .bottomLeading) {
                    CameraPreview(session: camera.session)
                    Button { camera.torchOn.toggle() } label: {
                        Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 20))
                            .frame(width: 48, height: 48)
                            .background(camera.torchOn ? Theme.sunlight : Theme.night.opacity(0.8))
                            .foregroundColor(camera.torchOn ? Theme.night : Theme.moon)
                            .clipShape(Circle())
                    }
                    .padding(14)
                    .accessibilityLabel(camera.torchOn ? "Turn torch off" : "Turn torch on")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius, style: .continuous))
            }

            HStack(spacing: 10) {
                ForEach(Array(shots.enumerated()), id: \.offset) { index, shot in
                    Image(uiImage: shot).resizable().scaledToFill()
                        .frame(width: 58, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { shots.remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.white)
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove photo \(index + 1)")
                        }
                }
                Spacer()
                Button(shots.count < maxShots ? "Take photo" : "3 photos max") { Task { await takePhoto() } }
                    .font(Theme.bodyStrong)
                    .foregroundColor(shots.count < maxShots ? Theme.sunlight : Theme.dusk)
                    .disabled(shots.count >= maxShots || busy)
            }

            Text("Take 1–3 photos from where you'll stand in the morning. One with the torch on and one with it off helps in the dark.")
                .font(Theme.caption)
                .foregroundColor(Theme.dusk)

            TextField("", text: $name, prompt: Text("Name, like Kettle").foregroundColor(Theme.dusk))
                .font(Theme.body)
                .foregroundColor(Theme.moon)
                .padding(14)
                .background(Theme.nightSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let error {
                Text(error).font(Theme.caption).foregroundColor(Theme.siren)
            }

            Spacer(minLength: 0)

            PrimaryButton(title: busy ? "Saving…" : "Save object") { save() }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 16)
        .background(Theme.night.ignoresSafeArea())
        .task { await camera.start() }
        .alert("This looks a lot like (lookalike?.name ?? "another object")",
               isPresented: Binding(get: { lookalike != nil }, set: { if !$0 { lookalike = nil } })) {
            Button("Save anyway") { save(allowLookalike: true) }
            Button("Retake", role: .cancel) { shots.removeAll() }
        } message: {
            Text("Look-alike objects make the morning photo harder to match. Pick something more distinct, or save anyway.")
        }
        .onDisappear { camera.stop() }
    }

    private var canSave: Bool {
        !busy && !shots.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func takePhoto() async {
        busy = true
        defer { busy = false }
        do {
            shots.append(try await camera.capture())
            error = nil
        } catch {
            self.error = "Couldn't take the photo. Try again."
        }
    }

    private func save(allowLookalike: Bool = false) {
        if !allowLookalike, let similar = model.lookalike(for: shots) {
            lookalike = similar
            return
        }
        busy = true
        defer { busy = false }
        do {
            if try model.addObject(name: name.trimmingCharacters(in: .whitespaces), photos: shots) {
                dismiss()
            } else {
                error = "Objects can't be changed right now."
            }
        } catch {
            self.error = "Couldn't save the photos. Try again."
        }
    }
}
