import SwiftUI

@main
struct EmergenceApp: App {

    @State private var appModel = AppModel()
    @State private var immersionStyle: ImmersionStyle = .mixed

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .onChange(of: appModel.immersionMode) { _, mode in
                    switch mode {
                    case .mixed: immersionStyle = .mixed
                    case .full:  immersionStyle = .full
                    }
                }
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear  { appModel.immersiveSpaceState = .open }
                .onDisappear { appModel.immersiveSpaceState = .closed }
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
        // visionOS 26: preserve any active Apple Environment (Yosemite, Moon, etc.)
        // rather than replacing it when the ImmersiveSpace opens.
        .immersiveEnvironmentBehavior(.coexist)
    }
}
