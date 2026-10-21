import SwiftUI
import AlarmyCore

struct MissionCameraView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var camera = CameraController(torchOn: true)
    @State private var toast: Toast?
    @State private var busy = false

    struct Toast: Equatable {
        let text: String
        let detail: String
        let isMiss: Bool
    }

    var body: some View {
        let object = model.currentObject
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.authorization == .denied || camera.authorization == .restricted {
                CameraAccessOff(message: "Camera access is off. Turn it on to stop the alarm.")
                    .foregroundColor(Theme.moon)
            } else {
                CameraPreview(session: camera.session).ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        (Text("Find: ").foregroundColor(Theme.moon) + Text(object?.name ?? "").foregroundColor(Theme.sunlight))
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Theme.night)
                            .clipShape(Capsule())
                        Spacer()
                        referenceThumbnail(object)
                    }

                    Spacer()

                    if let toast {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(toast.text).font(Theme.bodyStrong)
                            Text(toast.detail).font(.system(size: 13).monospacedDigit()).opacity(0.85)
                        }
                        .foregroundColor(toast.isMiss ? .white : Theme.night)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(toast.isMiss ? Theme.siren : Theme.sunlight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                        .padding(.bottom, 24)
                    }

                    ZStack {
                        Button(action: shoot) {
                            ZStack {
                                Circle().stroke(Theme.sunlight, lineWidth: 5).frame(width: 78, height: 78)
                                Circle().fill(busy ? Theme.dusk : .white).frame(width: 60, height: 60)
                                if busy { ProgressView().tint(Theme.night) }
                            }
                        }
                        .disabled(busy)
                        .accessibilityLabel("Take photo")

                        HStack {
                            Button { camera.torchOn.toggle() } label: {
                                Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.system(size: 20))
                                    .frame(width: 48, height: 48)
                                    .background(camera.torchOn ? Theme.sunlight : Theme.night.opacity(0.8))
                                    .foregroundColor(camera.torchOn ? Theme.night : Theme.moon)
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel(camera.torchOn ? "Turn torch off" : "Turn torch on")
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private func referenceThumbnail(_ object: RegisteredObject?) -> some View {
        Color.clear
            .frame(width: 78, height: 104)
            .background {
                if let id = object?.referencePhotoIDs.first, let image = model.photos.image(id) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.nightSurface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.sunlight, lineWidth: 3))
            .accessibilityLabel("Reference photo")
    }

    private func shoot() {
        busy = true
        Task {
            defer { busy = false }
            guard let photo = try? await camera.capture() else {
                toast = Toast(text: "Couldn't take the photo. Try again.", detail: "", isMiss: true)
                return
            }
            guard let result = await model.submitMissionPhoto(photo) else { return }
            switch result {
            case .matched:
                toast = nil
            case .miss(let distance, let threshold, let switchedTo):
                let detail = distance.isFinite
                    ? String(format: "Score %.1f, needs %.1f or lower", distance, threshold)
                    : "No reference photo to compare with"
                if let switchedTo {
                    toast = Toast(text: "Switched to \(switchedTo.name)", detail: detail, isMiss: false)
                } else {
                    toast = Toast(text: "Not a match. Get closer and try again.", detail: detail, isMiss: true)
                }
            }
        }
    }
}
