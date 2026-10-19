import AVFoundation
import Combine
import SwiftUI

private enum PracticeMode: String, CaseIterable {
    case explore = "Explore"
    case guess = "Guess"
}

struct RootNote: Identifiable, Equatable {
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

struct IntervalInfo: Identifiable {
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
    @State private var gamePhase: GamePhase = .setup
    @State private var roundLength = 10
    @State private var challenge: IntervalInfo?
    @State private var answer: IntervalInfo?
    @State private var attempts: [GuessAttempt] = []
    @State private var playCount = 0
    @State private var advanceTask: Task<Void, Never>?
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

                let horizontalPadding: CGFloat = geometry.size.width < 520 ? 16 : 28

                VStack(spacing: 0) {
                    if isGameActive {
                        gameHUD
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    GeometryReader { scrollGeometry in
                        // During a round the wheel grows to fill the space left by the panel.
                        let gameSide = max(280, min(scrollGeometry.size.width - horizontalPadding * 2, scrollGeometry.size.height - 40, 760))

                        ScrollView {
                            VStack(spacing: 28) {
                                if !isGameActive {
                                    header
                                }

                                if geometry.size.width >= 880 {
                                    HStack(alignment: .center, spacing: 24) {
                                        wheelCard
                                            .frame(width: isGameActive ? gameSide : min(geometry.size.width * 0.55, 620))
                                        if !isGameActive {
                                            practicePanel
                                                .frame(width: min(geometry.size.width * 0.33, 370))
                                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                        }
                                    }
                                    .frame(maxWidth: 1180)
                                } else {
                                    VStack(spacing: 20) {
                                        wheelCard
                                            .frame(maxWidth: isGameActive ? gameSide : 560)
                                        if !isGameActive {
                                            practicePanel
                                                .frame(maxWidth: 560)
                                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                        }
                                    }
                                }

                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, isGameActive ? 0 : 20)
                            .padding(.bottom, isGameActive ? 0 : 34)
                            .frame(maxWidth: .infinity, minHeight: isGameActive ? scrollGeometry.size.height : nil)
                        }
                        .scrollDisabled(isGameActive)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            advanceTask?.cancel()
            audio.stopAll()
        }
        .onChange(of: mode) {
            resetGame()
        }
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
                onSelect: chooseInterval
            ) { side in
                if isGameActive {
                    GameCenterBadge(
                        side: side,
                        root: selectedRoot,
                        questionNumber: min(attempts.count + (answer == nil ? 1 : 0), roundLength),
                        length: roundLength,
                        challenge: challenge,
                        answer: answer,
                        streak: attempts.currentStreak,
                        playCount: playCount,
                        action: gameCenterTapped
                    )
                } else {
                    RootNoteBadge(side: side, selectedRoot: selectedRoot, onSelect: selectRoot)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .padding(20)
        .background {
            // The card chrome fades away during a round so the circle stands on its own.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1B1D22), Color(hex: 0x15171B)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.17), radius: 26, x: 0, y: 16)
                .opacity(isGameActive ? 0 : 1)
        }
    }

    private var gameHUD: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                quitButton
                    .frame(width: 104, alignment: .leading)
                Spacer(minLength: 0)
                GameTrail(attempts: attempts, length: roundLength)
                Spacer(minLength: 0)
                gameScore
                    .frame(width: 104, alignment: .trailing)
            }

            VStack(spacing: 14) {
                HStack {
                    quitButton
                    Spacer()
                    gameScore
                }
                GameTrail(attempts: attempts, length: roundLength)
            }
        }
        .frame(maxWidth: 1180)
    }

    private var quitButton: some View {
        Button(action: quitGame) {
            HStack(spacing: 7) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Quit")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Color.panel, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Quit round")
        .accessibilityHint("Ends this round without scoring it")
    }

    private var gameScore: some View {
        HStack(spacing: 12) {
            if attempts.currentStreak >= 2 {
                Label("\(attempts.currentStreak)", systemImage: "flame.fill")
                    .foregroundStyle(Color.streakTint)
                    .transition(.scale.combined(with: .opacity))
            }
            Label("\(attempts.correctCount)", systemImage: "checkmark")
                .foregroundStyle(Color.correctTint)
                .contentTransition(.numericText())
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
        .labelStyle(.titleAndIcon)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: attempts.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(attempts.correctCount) correct, streak of \(attempts.currentStreak)")
    }

    private var practicePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(mode == .explore ? "Meet each interval" : (gamePhase == .finished ? "Round complete" : "Name what you hear"))
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

            if mode == .guess {
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
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: gamePhase)
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
            if gamePhase == .finished {
                HStack(spacing: 10) {
                    scoreTile(value: "\(attempts.correctCount)/\(attempts.count)", label: "CORRECT", tint: .correctTint)
                    scoreTile(value: "\(attempts.bestStreak)", label: "BEST STREAK", tint: .streakTint)
                }

                GameTrail(attempts: attempts, length: attempts.count)
                    .padding(.horizontal, 2)

                guessInfoCard(eyebrow: "HOW IT WENT", tint: resultsTint, title: resultsTitle, subtitle: resultsSubtitle)
            } else {
                guessInfoCard(
                    eyebrow: "HOW IT PLAYS",
                    tint: .accentTint,
                    title: "\(roundLength) notes, one tap each",
                    subtitle: "Each note sounds above \(selectedRoot.displayName). Tap its step on the circle and the next note follows on its own. Tap the center to hear it again."
                )
            }

            roundLengthPicker
        }
        .frame(minHeight: 198, alignment: .topLeading)
    }

    private func guessInfoCard(eyebrow: String, tint: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(Color.mutedText)
            }

            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .background(Color(hex: 0x121417), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var roundLengthPicker: some View {
        HStack(spacing: 10) {
            Text("NOTES PER ROUND")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.25)
                .foregroundStyle(Color.mutedText)

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                ForEach([5, 10, 20], id: \.self) { length in
                    Button {
                        roundLength = length
                    } label: {
                        Text("\(length)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(roundLength == length ? Color.primaryText : Color.secondaryText)
                            .frame(width: 38, height: 28)
                            .background {
                                if roundLength == length {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color(hex: 0x34343E))
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(length) notes per round")
                    .accessibilityAddTraits(roundLength == length ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color(hex: 0x121417), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var resultsAccuracy: Double {
        attempts.isEmpty ? 0 : Double(attempts.correctCount) / Double(attempts.count)
    }

    private var resultsTint: Color {
        resultsAccuracy >= 0.8 ? .correctTint : (resultsAccuracy >= 0.5 ? .streakTint : .wrongTint)
    }

    private var resultsTitle: String {
        switch resultsAccuracy {
        case 1: "Flawless round"
        case 0.8...: "Sharp ears"
        case 0.5...: "Getting there"
        default: "Keep listening"
        }
    }

    private var resultsSubtitle: String {
        let misses = Dictionary(grouping: attempts.filter { !$0.isCorrect }, by: \.target.semitones)
        guard !misses.isEmpty else { return "Every note landed above \(selectedRoot.displayName)." }

        let trickiest = misses
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(3)
            .map { semitones, missed in
                let name = IntervalInfo.semitones(semitones).name.lowercased()
                return missed.count > 1 ? "\(name) (×\(missed.count))" : name
            }
        return "Trickiest: \(trickiest.joined(separator: ", ")). Try them in Explore, then go again."
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
        Button(action: startGame) {
            HStack(spacing: 10) {
                Image(systemName: gamePhase == .finished ? "arrow.clockwise" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(gamePhase == .finished ? "Play again" : "Start round")
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
        .keyboardShortcut(.defaultAction)
        .accessibilityHint("Starts a round of \(roundLength) mystery notes")
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
        } else {
            submitGuess(interval)
        }
    }

    private var isGameActive: Bool { mode == .guess && gamePhase == .playing }

    private func startGame() {
        advanceTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            attempts = []
            challenge = nil
            answer = nil
            gamePhase = .playing
        }
        // Give the layout a beat to settle before the first note sounds.
        scheduleNextQuestion(after: .milliseconds(650))
    }

    private func submitGuess(_ interval: IntervalInfo) {
        guard isGameActive, let challenge, answer == nil else { return }
        let attempt = GuessAttempt(id: attempts.count, target: challenge, guess: interval)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            answer = interval
            attempts.append(attempt)
        }
        // Misses linger longer so the right answer has time to register.
        scheduleNextQuestion(after: attempt.isCorrect ? .milliseconds(850) : .milliseconds(2000))
    }

    private func nextQuestion() {
        advanceTask?.cancel()
        guard isGameActive else { return }
        guard attempts.count < roundLength else {
            finishGame()
            return
        }

        let candidates = IntervalInfo.all.filter { $0.semitones != challenge?.semitones }
        let next = candidates.randomElement() ?? IntervalInfo.semitones(7)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            challenge = next
            answer = nil
        }
        playChallenge()
    }

    private func scheduleNextQuestion(after delay: Duration) {
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            nextQuestion()
        }
    }

    private func playChallenge() {
        guard let challenge else { return }
        playCount += 1
        audio.playInterval(semitones: challenge.semitones, rootFrequency: selectedRoot.frequency)
    }

    private func gameCenterTapped() {
        if answer != nil {
            nextQuestion()
        } else {
            playChallenge()
        }
    }

    private func finishGame() {
        advanceTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            challenge = nil
            answer = nil
            gamePhase = .finished
        }
    }

    private func quitGame() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            resetGame()
        }
    }

    private func resetGame() {
        advanceTask?.cancel()
        attempts = []
        challenge = nil
        answer = nil
        gamePhase = .setup
    }

    private func selectRoot(_ root: RootNote) {
        selectedRoot = root
        audio.playRootNote(frequency: root.frequency)
        audio.updateDrone(rootFrequency: root.frequency)
    }
}

private struct IntervalWheel<Center: View>: View {
    let selectedSemitones: Int?
    let revealedSemitones: Int?
    let onSelect: (IntervalInfo) -> Void
    @ViewBuilder let centerContent: (_ side: CGFloat) -> Center

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

                centerContent(side)

                ForEach(IntervalInfo.all) { interval in
                    let radians = Double(interval.wheelPosition) * Double.pi / 6 - Double.pi / 2
                    let labelRadius = side * 0.29
                    let ring = ringColor(for: interval)
                    IntervalWheelNode(
                        interval: interval,
                        isSelected: selectedSemitones == interval.semitones,
                        ringColor: ring,
                        isDimmed: revealedSemitones != nil && ring == nil,
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

    /// Once an answer is revealed, the right step glows green and a wrong pick glows red.
    private func ringColor(for interval: IntervalInfo) -> Color? {
        guard let revealedSemitones else { return nil }
        if interval.semitones == revealedSemitones { return .correctTint }
        if interval.semitones == selectedSemitones { return .wrongTint }
        return nil
    }
}

private struct RootNoteBadge: View {
    let side: CGFloat
    let selectedRoot: RootNote
    let onSelect: (RootNote) -> Void

    var body: some View {
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
    let ringColor: Color?
    let isDimmed: Bool
    let radialAngle: Double
    let markerOffset: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let ringColor {
                    Circle()
                        .stroke(ringColor.opacity(0.95), lineWidth: 2)
                        .frame(width: 60, height: 60)
                        .shadow(color: ringColor.opacity(0.5), radius: 10)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
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
            .scaleEffect(ringColor == nil ? 1 : 1.1)
            .opacity(isDimmed ? 0.4 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ringColor == nil)
        .animation(.easeInOut(duration: 0.2), value: isDimmed)
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

extension Color {
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
