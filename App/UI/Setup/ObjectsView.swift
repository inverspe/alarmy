import SwiftUI
import AlarmyCore

struct ObjectsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var adding = false
    @State private var pendingDelete: RegisteredObject?
    @State private var message: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Objects")

                if let holder = model.lockHolder {
                    LockBanner(text: "Locked until your \(Theme.timeString(holder.fireDate)) alarm is done")
                        .padding(.bottom, 14)
                }

                Text("Pick things that don't move, in rooms away from your bed. One is chosen at random each morning.")
                    .font(Theme.caption)
                    .foregroundColor(Theme.dusk)
                    .padding(.bottom, 16)

                if model.state.objects.isEmpty {
                    Text("No objects yet. Add at least three so mornings vary.")
                        .font(Theme.body)
                        .foregroundColor(Theme.moon)
                        .padding(.bottom, 16)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.state.objects) { object in
                        ObjectTile(object: object, image: object.referencePhotoIDs.first.flatMap(model.photos.image))
                            .contextMenu {
                                if !model.isLocked {
                                    Button("Delete \(object.name)", role: .destructive) { pendingDelete = object }
                                }
                            }
                    }
                }

                if let message {
                    Text(message).font(Theme.caption).foregroundColor(Theme.siren).padding(.top, 12)
                }

                PrimaryButton(title: "Add object", background: Theme.nightSurface, foreground: Theme.moon) {
                    adding = true
                }
                .padding(.top, 24)
                .disabled(model.isLocked)
                .opacity(model.isLocked ? 0.4 : 1)

                if !model.state.objects.isEmpty {
                    Text("Press and hold an object to delete it.")
                        .font(Theme.caption)
                        .foregroundColor(Theme.dusk)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.night.ignoresSafeArea())
        .fullScreenCover(isPresented: $adding) {
            AddObjectView().environmentObject(model)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "object")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let object = pendingDelete {
                    message = model.deleteObject(object.id)
                        ? nil
                        : (model.isLocked ? "Objects can't be changed right now."
                                          : "Keep at least one object while an alarm is on.")
                }
                pendingDelete = nil
            }
        }
    }
}

struct ObjectTile: View {
    let object: RegisteredObject
    let image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .background {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.nightSurface
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(object.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
