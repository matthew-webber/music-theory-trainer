import AVFoundation
import Combine
import SwiftUI

private enum PracticeMode: String, CaseIterable {
    case explore = "Explore"
    case guess = "Guess"
}

private struct RootNote: Identifiable, Equatable {
    let pitchClass: Int
    let name: String

    var id: Int { pitchClass }
    var midiNote: Int { 48 + pitchClass }
    var frequency: Double { 130.8128 * pow(2, Double(pitchClass) / 12) }
    var displayName: String { "\(name)3" }

    static let all: [RootNote] = [
        .init(pitchClass: 0, name: "C"), .init(pitchClass: 1, name: "C♯"),
        .init(pitchClass: 2, name: "D"), .init(pitchClass: 3, name: "E♭"),
        .init(pitchClass: 4, name: "E"), .init(pitchClass: 5, name: "F"),
        .init(pitchClass: 6, name: "F♯"), .init(pitchClass: 7, name: "G"),
        .init(pitchClass: 8, name: "A♭"), .init(pitchClass: 9, name: "A"),
        .init(pitchClass: 10, name: "B♭"), .init(pitchClass: 11, name: "B")
    ]

    static func noteName(for midiNote: Int) -> String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return "\(names[midiNote % 12])\(midiNote / 12 - 1)"
    }
}

private struct IntervalInfo: Identifiable {
    let semitones: Int
    let symbol: String
    let name: String
    let defaultFeelingTags: [String]
    let color: Color
    let wheelPosition: Int

    var id: Int { semitones }

    func targetNote(for root: RootNote) -> String {
        RootNote.noteName(for: root.midiNote + semitones)
    }

    static let all: [IntervalInfo] = [
        .init(semitones: 0, symbol: "1", name: "Perfect unison", defaultFeelingTags: ["still", "centered", "resolved"], color: Color(hex: 0x625EFF), wheelPosition: 0),
        .init(semitones: 7, symbol: "5", name: "Perfect fifth", defaultFeelingTags: ["open", "steady", "resonant"], color: Color(hex: 0xB85CFF), wheelPosition: 1),
        .init(semitones: 2, symbol: "2", name: "Major second", defaultFeelingTags: ["bright", "expectant", "moving"], color: Color(hex: 0xF04FDF), wheelPosition: 2),
        .init(semitones: 9, symbol: "6", name: "Major sixth", defaultFeelingTags: ["warm", "hopeful", "expansive"], color: Color(hex: 0xF15AAE), wheelPosition: 3),
        .init(semitones: 4, symbol: "3", name: "Major third", defaultFeelingTags: ["bright", "confident", "lifted"], color: Color(hex: 0xFF646B), wheelPosition: 4),
        .init(semitones: 11, symbol: "7", name: "Major seventh", defaultFeelingTags: ["shimmering", "longing", "unresolved"], color: Color(hex: 0xFFB85E), wheelPosition: 5),
        .init(semitones: 6, symbol: "♯4", name: "Tritone", defaultFeelingTags: ["electric", "unstable", "searching"], color: Color(hex: 0xFFF15C), wheelPosition: 6),
        .init(semitones: 1, symbol: "♭2", name: "Minor second", defaultFeelingTags: ["tense", "close", "unsettled"], color: Color(hex: 0xA8F35A), wheelPosition: 7),
        .init(semitones: 8, symbol: "♭6", name: "Minor sixth", defaultFeelingTags: ["wistful", "cinematic", "yearning"], color: Color(hex: 0x69F067), wheelPosition: 8),
        .init(semitones: 3, symbol: "♭3", name: "Minor third", defaultFeelingTags: ["warm", "reflective", "gentle"], color: Color(hex: 0x55ECA9), wheelPosition: 9),
        .init(semitones: 10, symbol: "♭7", name: "Minor seventh", defaultFeelingTags: ["bluesy", "familiar", "unresolved"], color: Color(hex: 0x4CE8EB), wheelPosition: 10),
        .init(semitones: 5, symbol: "4", name: "Perfect fourth", defaultFeelingTags: ["open", "spacious", "suspended"], color: Color(hex: 0x65B9FF), wheelPosition: 11)
    ]

    static func semitones(_ value: Int) -> IntervalInfo {
        all.first(where: { $0.semitones == value }) ?? all[0]
    }
}

struct ContentView: View {
    @StateObject private var audio = IntervalAudio()
    @State private var mode: PracticeMode = .explore
    @State private var selectedInterval = IntervalInfo.semitones(7)
    @State private var selectedRoot = RootNote.all[0]
    @State private var challenge: IntervalInfo?
    @State private var answer: IntervalInfo?
    @State private var correctCount = 0
    @State private var roundCount = 0
    @State private var isFeelingExpanded = true
    @State private var isAddTagPresented = false
    @State private var newFeelingTag = ""
    @State private var isSettingsPresented = false
    @State private var removedDefaultTags: [Int: Set<String>] = [:]
    @State private var customFeelingTags: [Int: [String]] = [:]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [Color(hex: 0x22212E).opacity(0.72), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 780
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        header

                        if geometry.size.width >= 880 {
                            HStack(alignment: .center, spacing: 24) {
                                wheelCard
                                    .frame(width: min(geometry.size.width * 0.55, 620))
                                practicePanel
                                    .frame(width: min(geometry.size.width * 0.33, 370))
                            }
                            .frame(maxWidth: 1180)
                        } else {
                            VStack(spacing: 20) {
                                wheelCard
                                    .frame(maxWidth: 560)
                                practicePanel
                                    .frame(maxWidth: 560)
                            }
                        }

                    }
                    .padding(.horizontal, geometry.size.width < 520 ? 16 : 28)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { audio.stopAll() }
        .alert("Add a feeling tag", isPresented: $isAddTagPresented) {
            TextField("e.g. wistful", text: $newFeelingTag)
            Button("Add", action: addFeelingTag)
                .disabled(newFeelingTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { newFeelingTag = "" }
        } message: {
            Text("Add a personal cue for \(selectedInterval.name.lowercased()).")
        }
        .sheet(isPresented: $isSettingsPresented) {
            FeelingSettingsSheet(onRestoreDefaults: restoreDefaultFeelingTags)
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(maxWidth: 1180)
    }

    private var wheelCard: some View {
        VStack {
            IntervalWheel(
                selectedSemitones: mode == .explore ? selectedInterval.semitones : answer?.semitones,
                revealedSemitones: mode == .guess && answer != nil ? challenge?.semitones : nil,
                root: selectedRoot,
                onSelect: chooseInterval,
                onSelectRoot: selectRoot
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1B1D22), Color(hex: 0x15171B)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.17), radius: 26, x: 0, y: 16)
    }

    private var practicePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(mode == .explore ? "Meet each interval" : "Name what you hear")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            modePicker

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            if mode == .explore {
                exploreDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                guessDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if mode == .guess && (challenge == nil || answer != nil) {
                primaryAction
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            droneControl
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.panel)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.19), radius: 24, x: 0, y: 14)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: mode)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: answer?.semitones)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(PracticeMode.allCases, id: \.self) { item in
                Button {
                    mode = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item == .explore ? "sparkles" : "questionmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(mode == item ? Color.primaryText : Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if mode == item {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: 0x34343E))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(hex: 0x121417), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var exploreDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle().fill(selectedInterval.color).frame(width: 8, height: 8)
                    Text("CURRENT INTERVAL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(Color.mutedText)
                }
                Text(selectedInterval.name)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                Text("\(selectedRoot.displayName)  →  \(selectedInterval.targetNote(for: selectedRoot))  ·  \(selectedInterval.semitones) semitones")
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.secondaryText)
            }

            if isFeelingExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("FEELING TAGS")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.25)
                            .foregroundStyle(Color.secondaryText)
                        Spacer()
                        Button {
                            newFeelingTag = ""
                            isAddTagPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0xA29BFF))
                                .frame(width: 28, height: 28)
                                .background(Color(hex: 0x7870F7).opacity(0.13), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a feeling tag")

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                isFeelingExpanded = false
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.secondaryText)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse feeling tags")
                    }

                    let tags = visibleFeelingTags(for: selectedInterval)
                    if tags.isEmpty {
                        Button {
                            newFeelingTag = ""
                            isAddTagPresented = true
                        } label: {
                            Text("Add your first cue")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.mutedText)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(tags, id: \.self) { tag in
                                    feelingTagChip(tag)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                .padding(11)
                .background(Color(hex: 0x121417), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
            } else {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        isFeelingExpanded = true
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedInterval.color)
                        .frame(width: 32, height: 32)
                        .background(selectedInterval.color.opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show feeling tags")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isFeelingExpanded)
        .animation(.easeInOut(duration: 0.2), value: selectedInterval.semitones)
    }

    private var guessDetails: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                scoreTile(value: "\(correctCount)", label: "CORRECT", tint: Color(hex: 0x75E4C1))
                scoreTile(value: "\(roundCount)", label: "ROUNDS", tint: Color(hex: 0xA29BFF))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(answer == nil ? Color(hex: 0xA29BFF) : (answer?.semitones == challenge?.semitones ? Color(hex: 0x75E4C1) : Color(hex: 0xFF8A82)))
                        .frame(width: 8, height: 8)
                    Text(guessEyebrow)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(Color.mutedText)
                }

                Text(guessTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(guessSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .background(Color(hex: 0x121417), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(minHeight: 198, alignment: .topLeading)
    }

    private var guessEyebrow: String {
        guard let challenge else { return "READY WHEN YOU ARE" }
        guard let answer else { return "MYSTERY INTERVAL" }
        return answer.semitones == challenge.semitones ? "THAT’S IT" : "NOT QUITE — TRY AGAIN NEXT ROUND"
    }

    private var guessTitle: String {
        guard let challenge else { return "Start with a listening round" }
        guard let answer else { return "Listen, then pick a point" }
        return answer.semitones == challenge.semitones ? challenge.name : "It was the \(challenge.name.lowercased())"
    }

    private var guessSubtitle: String {
        guard let challenge else { return "One note will play. Identify its interval above \(selectedRoot.displayName)." }
        guard let answer else { return "Use the colored steps to identify the sound." }
        let tags = visibleFeelingTags(for: challenge).joined(separator: " · ")
        let feelingCue = tags.isEmpty ? "" : " · \(tags)"
        return "You chose \(answer.name.lowercased()). \(selectedRoot.displayName) → \(challenge.targetNote(for: selectedRoot)) · \(challenge.semitones) semitones\(feelingCue)"
    }

    private func visibleFeelingTags(for interval: IntervalInfo) -> [String] {
        let removed = removedDefaultTags[interval.id] ?? []
        let defaults = interval.defaultFeelingTags.filter { !removed.contains($0) }
        return defaults + (customFeelingTags[interval.id] ?? [])
    }

    private func feelingTagChip(_ tag: String) -> some View {
        Button {
            removeFeelingTag(tag, from: selectedInterval)
        } label: {
            Text(tag)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedInterval.color.opacity(0.97))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(selectedInterval.color.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(selectedInterval.color.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove feeling tag \(tag)")
        .accessibilityHint("Removes this tag from \(selectedInterval.name)")
    }

    private func removeFeelingTag(_ tag: String, from interval: IntervalInfo) {
        if interval.defaultFeelingTags.contains(tag) {
            var removed = removedDefaultTags[interval.id] ?? []
            removed.insert(tag)
            removedDefaultTags[interval.id] = removed
        } else {
            customFeelingTags[interval.id]?.removeAll { $0 == tag }
        }
    }

    private func addFeelingTag() {
        let tag = newFeelingTag.trimmingCharacters(in: .whitespacesAndNewlines)
        newFeelingTag = ""
        guard !tag.isEmpty else { return }

        if let matchingDefault = selectedInterval.defaultFeelingTags.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            var removed = removedDefaultTags[selectedInterval.id] ?? []
            removed.remove(matchingDefault)
            removedDefaultTags[selectedInterval.id] = removed
            return
        }

        let existing = visibleFeelingTags(for: selectedInterval)
        guard !existing.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        customFeelingTags[selectedInterval.id, default: []].append(tag)
    }

    private func restoreDefaultFeelingTags() {
        removedDefaultTags.removeAll()
    }

    private func scoreTile(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color(hex: 0x121417), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var primaryAction: some View {
        Button(action: beginRound) {
            HStack(spacing: 10) {
                Image(systemName: "shuffle")
                    .font(.system(size: 14, weight: .bold))
                Text("Start a new round")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 17)
            .frame(height: 52)
            .background(LinearGradient(colors: [Color(hex: 0x7771F5), Color(hex: 0x8D68E9)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x776DF0).opacity(0.2), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts a new round and plays one mystery note")
    }

    private var droneControl: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("\(selectedRoot.name) drone")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
            }

            Spacer(minLength: 4)

            Toggle("Drone", isOn: Binding(
                get: { audio.isDronePlaying },
                set: { audio.setDrone($0, rootFrequency: selectedRoot.frequency) }
            ))
            .labelsHidden()
            .tint(Color(hex: 0x64DDB8))
            .accessibilityLabel("\(selectedRoot.name) drone")
        }
        .padding(.top, 1)
    }

    private func chooseInterval(_ interval: IntervalInfo) {
        if mode == .explore {
            selectedInterval = interval
            audio.playInterval(semitones: interval.semitones, rootFrequency: selectedRoot.frequency)
        } else if let challenge, answer == nil {
            answer = interval
            roundCount += 1
            if interval.semitones == challenge.semitones {
                correctCount += 1
            }
        }
    }

    private func beginRound() {
        let candidates = IntervalInfo.all.filter { $0.semitones != challenge?.semitones }
        challenge = candidates.randomElement() ?? IntervalInfo.semitones(7)
        answer = nil
        audio.playInterval(semitones: challenge?.semitones ?? 7, rootFrequency: selectedRoot.frequency)
    }

    private func selectRoot(_ root: RootNote) {
        selectedRoot = root
        audio.playRootNote(frequency: root.frequency)
        audio.updateDrone(rootFrequency: root.frequency)
    }
}

private struct IntervalWheel: View {
    let selectedSemitones: Int?
    let revealedSemitones: Int?
    let root: RootNote
    let onSelect: (IntervalInfo) -> Void
    let onSelectRoot: (RootNote) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = side / 2

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: side * 0.78, height: side * 0.78)

                Circle()
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
                    .frame(width: side * 0.53, height: side * 0.53)

                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0x272833).opacity(0.8), Color(hex: 0x191B20).opacity(0.24)], center: .center, startRadius: 6, endRadius: side * 0.26))
                    .frame(width: side * 0.48, height: side * 0.48)

                rootBadge(side: side, selectedRoot: root, onSelect: onSelectRoot)

                ForEach(IntervalInfo.all) { interval in
                    let radians = Double(interval.wheelPosition) * Double.pi / 6 - Double.pi / 2
                    let labelRadius = side * 0.29
                    IntervalWheelNode(
                        interval: interval,
                        isSelected: selectedSemitones == interval.semitones,
                        isRevealedTarget: revealedSemitones == interval.semitones && selectedSemitones != interval.semitones,
                        radialAngle: radians,
                        markerOffset: side * 0.10,
                        action: { onSelect(interval) }
                    )
                    .position(
                        x: center + CGFloat(cos(radians)) * labelRadius,
                        y: center + CGFloat(sin(radians)) * labelRadius
                    )
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interval circle. Select one of twelve semitone steps.")
    }

    private func rootBadge(side: CGFloat, selectedRoot: RootNote, onSelect: @escaping (RootNote) -> Void) -> some View {
        Menu {
            Section("Root note · octave 3") {
                ForEach(RootNote.all) { note in
                    Button {
                        onSelect(note)
                    } label: {
                        if note == selectedRoot {
                            Label(note.displayName, systemImage: "checkmark")
                        } else {
                            Text(note.displayName)
                        }
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color(hex: 0x17191E))
                .overlay(Circle().stroke(Color.white.opacity(0.09), lineWidth: 1))
                .overlay {
                    VStack(spacing: 5) {
                        Text("ROOT NOTE")
                            .font(.system(size: max(8, side * 0.018), weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(Color.mutedText)
                        Text(selectedRoot.displayName)
                            .font(.system(size: side * 0.095, weight: .light, design: .rounded))
                            .foregroundStyle(Color.primaryText)
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: max(6, side * 0.014), weight: .bold))
                            Text("CHANGE KEY")
                                .font(.system(size: max(7, side * 0.016), weight: .bold, design: .rounded))
                                .tracking(1.1)
                        }
                        .foregroundStyle(Color.secondaryText)
                    }
                    .minimumScaleFactor(0.75)
                }
                .frame(width: side * 0.40, height: side * 0.40)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel("Root note \(selectedRoot.displayName). Choose a new root note.")
    }
}

private struct IntervalWheelNode: View {
    let interval: IntervalInfo
    let isSelected: Bool
    let isRevealedTarget: Bool
    let radialAngle: Double
    let markerOffset: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRevealedTarget {
                    Circle()
                        .stroke(Color(hex: 0x75E4C1).opacity(0.95), lineWidth: 1.5)
                        .frame(width: 58, height: 58)
                        .shadow(color: Color(hex: 0x75E4C1).opacity(0.4), radius: 8)
                }

                Circle()
                    .fill(isSelected ? interval.color.opacity(0.2) : Color(hex: 0x1A1C21))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(isSelected ? interval.color.opacity(0.95) : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 1))
                    .shadow(color: isSelected ? interval.color.opacity(0.3) : .clear, radius: 12, x: 0, y: 0)

                Text(interval.symbol)
                    .font(.system(size: 17, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color(hex: 0xD0D1D8))

                Circle()
                    .fill(interval.color)
                    .frame(width: isSelected ? 13 : 10, height: isSelected ? 13 : 10)
                    .overlay(Circle().stroke(Color(hex: 0x17191E), lineWidth: 2))
                    .shadow(color: interval.color.opacity(isSelected ? 0.7 : 0.28), radius: isSelected ? 8 : 3)
                    .offset(x: cos(radialAngle) * Double(markerOffset), y: sin(radialAngle) * Double(markerOffset))
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(interval.name), \(interval.semitones) semitones")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FeelingSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var didRestoreDefaults = false
    let onRestoreDefaults: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0xB2ACFF))
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Text("Feeling tags")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                Text("Restore the original tags removed from interval cards. Your personal tags stay.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onRestoreDefaults()
                    didRestoreDefaults = true
                } label: {
                    Label("Restore original tags", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 3)

                if didRestoreDefaults {
                    Text("Original tags restored.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: 0x75E4C1))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 460, minHeight: 270, alignment: .topLeading)
        .background(Color.canvas)
    }
}

@MainActor
private final class IntervalAudio: ObservableObject {
    @Published private(set) var isDronePlaying = false

    private let engine = AVAudioEngine()
    private let dronePlayer = AVAudioPlayerNode()
    private let intervalPlayer = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private var isConfigured = false

    func setDrone(_ enabled: Bool, rootFrequency: Double) {
        if enabled {
            guard startEngine() else { return }
            dronePlayer.stop()
            dronePlayer.scheduleBuffer(makeDroneBuffer(rootFrequency: rootFrequency), at: nil, options: .loops, completionHandler: nil)
            dronePlayer.play()
            isDronePlaying = true
        } else {
            dronePlayer.stop()
            isDronePlaying = false
        }
    }

    func updateDrone(rootFrequency: Double) {
        guard isDronePlaying else { return }
        setDrone(true, rootFrequency: rootFrequency)
    }

    func playRootNote(frequency: Double) {
        guard startEngine() else { return }
        intervalPlayer.stop()
        intervalPlayer.scheduleBuffer(makeNoteBuffer(frequency: frequency), at: nil, options: [], completionHandler: nil)
        intervalPlayer.play()
    }

    func playInterval(semitones: Int, rootFrequency: Double) {
        guard startEngine() else { return }
        intervalPlayer.stop()
        intervalPlayer.scheduleBuffer(makeIntervalBuffer(semitones: semitones, rootFrequency: rootFrequency), at: nil, options: [], completionHandler: nil)
        intervalPlayer.play()
    }

    func stopAll() {
        dronePlayer.stop()
        intervalPlayer.stop()
        if engine.isRunning { engine.stop() }
        isDronePlaying = false
    }

    private func startEngine() -> Bool {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        if !isConfigured {
            engine.attach(dronePlayer)
            engine.attach(intervalPlayer)
            engine.connect(dronePlayer, to: engine.mainMixerNode, format: audioFormat)
            engine.connect(intervalPlayer, to: engine.mainMixerNode, format: audioFormat)
            engine.prepare()
            isConfigured = true
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return false
            }
        }
        return true
    }

    private var audioFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    private func makeDroneBuffer(rootFrequency: Double) -> AVAudioPCMBuffer {
        // The loop is sized to an integer number of cycles at the selected root's lower octave.
        let fundamental = rootFrequency / 2
        let frameCount = AVAudioFrameCount((sampleRate / fundamental * 64).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let swell = 0.9 + 0.1 * sin(2 * Double.pi * 4 * Double(frame) / Double(frameCount))
            let bass = warmTone(frequency: fundamental, time: t)
            let root = warmTone(frequency: fundamental * 2, time: t) * 0.52
            let fifth = warmTone(frequency: fundamental * 3, time: t) * 0.34
            let octave = warmTone(frequency: fundamental * 4, time: t) * 0.18
            let value = Float((bass + root + fifth + octave) * 0.075 * swell)
            channels[0][frame] = value
            channels[1][frame] = value * 0.96
        }
        return buffer
    }

    private func makeNoteBuffer(frequency: Double) -> AVAudioPCMBuffer {
        let duration = 1.05
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let attack = min(1, t / 0.025)
            let release = min(1, (duration - t) / 0.22)
            let value = Float(warmTone(frequency: frequency, time: t) * 0.25 * max(0, min(attack, release)))
            channels[0][frame] = value
            channels[1][frame] = value
        }
        return buffer
    }

    private func makeIntervalBuffer(semitones: Int, rootFrequency: Double) -> AVAudioPCMBuffer {
        let duration = 2.15
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return buffer }

        let targetFrequency = rootFrequency * pow(2, Double(semitones) / 12)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let attack = min(1, t / 0.035)
            let release = min(1, (duration - t) / 0.28)
            let envelope = max(0, min(attack, release))
            let target = warmTone(frequency: targetFrequency, time: t)
            let value = Float(target * 0.25 * envelope)
            channels[0][frame] = value
            channels[1][frame] = value
        }
        return buffer
    }

    private func warmTone(frequency: Double, time: Double) -> Double {
        let phase = 2 * Double.pi * frequency * time
        return sin(phase) + 0.18 * sin(phase * 2) + 0.055 * sin(phase * 3)
    }
}

private extension Color {
    static let canvas = Color(hex: 0x111316)
    static let panel = Color(hex: 0x1C1F24)
    static let primaryText = Color(hex: 0xF4F3F7)
    static let secondaryText = Color(hex: 0xA8A9B3)
    static let mutedText = Color(hex: 0x70727D)

    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

#Preview {
    ContentView()
}
