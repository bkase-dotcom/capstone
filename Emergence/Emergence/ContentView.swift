import SwiftUI
import RealityKitContent

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var pickerN: Int = 1
    @State private var pickerL: Int = 0
    @State private var pickerM: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                simulationSection
                currentStateSection
                statePickerSection
                photonSection
                Section("Interaction") {
                    @Bindable var model = appModel
                    Toggle("Photon Firing", isOn: $model.photonFiringEnabled)
                }
                Section("Space") {
                    @Bindable var model = appModel
                    Picker("Mode", selection: $model.immersionMode) {
                        ForEach(AppModel.ImmersionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Group {
                        switch model.immersionMode {
                        case .mixed:
                            VStack(alignment: .leading, spacing: 4) {
                                Text("The atom floats in your real world or any Apple Environment you've selected — the environment stays active.")
                                Text("→ To use an Apple environment: swipe down for Control Center → Environments, choose a scene (Yosemite, Moon, etc.), then tap Enter Immersive Space.")
                            }
                        case .full:
                            Text("Pitch black quantum space — best for clearly seeing the orbital structure. Windows always render in front of the atom in this mode (visionOS system limitation).")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section { ToggleImmersiveSpaceButton() }
            }
            .navigationTitle("Emergence")
            .onAppear { syncPickers(to: appModel.atomState.orbitalState) }
            .onChange(of: appModel.atomState.orbitalState) { _, s in
                syncPickers(to: s)
            }
        }
    }

    private func syncPickers(to s: OrbitalState) {
        pickerN = s.n; pickerL = s.l; pickerM = s.m
    }

    // MARK: - Simulation

    private var simulationSection: some View {
        Section("Simulation") {
            Label("Hydrogen Atom", systemImage: "atom")
                .font(.headline)
            Text("Bound states n = 1 – \(HydrogenPhysics.nMax), dipole (E1) selection rules, real spherical harmonics.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Current state

    private var currentStateSection: some View {
        Section("Current State") {
            if appModel.atomState.isIonized {
                Label("Ionized — recombining…", systemImage: "bolt.fill")
                    .foregroundStyle(.yellow)
            } else {
                let s      = appModel.atomState.orbitalState
                let letter = HydrogenPhysics.orbitalLetter[s.l] ?? "?"
                let mLabel = s.m >= 0 ? "+\(s.m)" : "\(s.m)"

                LabeledContent("Orbital") {
                    Text("\(s.n)\(letter)   m = \(mLabel)")
                        .font(.headline.monospacedDigit())
                }
                LabeledContent("Binding energy") {
                    Text(String(format: "%.4f eV", HydrogenPhysics.energyLevel(s.n)))
                        .monospacedDigit()
                }
                LabeledContent("Degeneracy") {
                    Text("\(s.n * s.n) substates at this n")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - State picker

    private var statePickerSection: some View {
        Section("Set Quantum State") {
            Picker("n  (principal)", selection: $pickerN) {
                ForEach(1...HydrogenPhysics.nMax, id: \.self) { n in
                    Text("n = \(n)").tag(n)
                }
            }
            .onChange(of: pickerN) {
                if pickerL >= pickerN { pickerL = pickerN - 1 }
                pickerM = max(-pickerL, min(pickerM, pickerL))
            }

            Picker("ℓ  (angular)", selection: $pickerL) {
                ForEach(0..<pickerN, id: \.self) { l in
                    Text("ℓ = \(l)  (\(HydrogenPhysics.orbitalLetter[l] ?? "?"))").tag(l)
                }
            }
            .onChange(of: pickerL) {
                pickerM = max(-pickerL, min(pickerM, pickerL))
            }

            Picker("m  (magnetic)", selection: $pickerM) {
                ForEach(Array(-pickerL...pickerL), id: \.self) { m in
                    Text("m = \(m >= 0 ? "+\(m)" : "\(m)")").tag(m)
                }
            }

            Button("Apply State") {
                appModel.atomState.forceSetState(
                    OrbitalState(n: pickerN, l: pickerL, m: pickerM))
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.atomState.isIonized)
        }
    }

    // MARK: - Photon energy

    private var photonSection: some View {
        Section("Photon Energy") {
            photonColorRow
            photonSlider
            transitionSnapButtons
        }
    }

    private var photonColorRow: some View {
        let ev  = appModel.atomState.dialedPhotonEv
        let nm  = HydrogenPhysics.hcEvNm / ev
        let rgb = HydrogenPhysics.wavelengthToRGB(nm)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                .frame(width: 44, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(.white.opacity(0.2), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.3f eV", ev))
                    .font(.headline.monospacedDigit())
                Text(String(format: "%.1f nm", nm))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                if appModel.atomState.dialedEnergyIsResonant {
                    Label("Resonant", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if appModel.atomState.dialedEnergyIonizes {
                    Label("Ionizes", systemImage: "bolt.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Label("Off resonance", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    private var photonSlider: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { appModel.atomState.dialedPhotonEv },
                    set: { appModel.atomState.dialedPhotonEv = $0 }
                ),
                in: 1.5...14.0,
                step: 0.01
            )
            HStack {
                Text("1.5 eV").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("14.0 eV  (≥ ionization)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var transitionSnapButtons: some View {
        let transitions = appModel.atomState.availableTransitionEnergies
        let ionE        = HydrogenPhysics.ionizationEnergy(appModel.atomState.orbitalState.n)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Snap to resonance:")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(transitions, id: \.nHi) { t in
                        snapButton(label: "→n=\(t.nHi)", ev: t.ev)
                    }
                    snapButton(label: "⚡ ionize", ev: ionE)
                        .tint(.yellow)
                }
                .padding(.vertical, 4)
            }
        }
        .disabled(appModel.atomState.isIonized)
    }

    private func snapButton(label: String, ev: Double) -> some View {
        let nm  = HydrogenPhysics.hcEvNm / ev
        let rgb = HydrogenPhysics.wavelengthToRGB(nm)
        return Button {
            appModel.atomState.dialedPhotonEv = ev
        } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                    .frame(width: 32, height: 10)
                Text(label).font(.caption2)
                Text(String(format: "%.2f eV", ev))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.bordered)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
