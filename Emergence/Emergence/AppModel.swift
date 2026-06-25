import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    /// Controls which immersion style the ImmersiveSpace uses.
    enum ImmersionMode: String, CaseIterable, Hashable {
        case mixed = "Mixed Reality"
        case full  = "Quantum Realm"
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var photonFiringEnabled = true
    var immersionMode: ImmersionMode = .mixed

    let atomState = AtomStateMachine()
}
