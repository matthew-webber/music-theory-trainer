import SwiftUI

enum GamePhase {
    case setup
    case playing
    case finished
}

struct GuessAttempt: Identifiable {
    let id: Int
    let target: IntervalInfo
    let guess: IntervalInfo

    var isCorrect: Bool { target.semitones == guess.semitones }
}

extension Array where Element == GuessAttempt {
    var correctCount: Int { filter(\.isCorrect).count }

    var currentStreak: Int { reversed().prefix(while: \.isCorrect).count }

    var bestStreak: Int {
        var best = 0
        var run = 0
        for attempt in self {
            run = attempt.isCorrect ? run + 1 : 0
            best = Swift.max(best, run)
        }
        return best
    }
}

extension Color {
    static let correctTint = Color(hex: 0x75E4C1)
    static let wrongTint = Color(hex: 0xFF8A82)
    static let accentTint = Color(hex: 0xA29BFF)
    static let streakTint = Color(hex: 0xFFB85E)
}

/// One pill per note in the round: filled in as the player answers, with the current note stretched.
struct GameTrail: View {
    let attempts: [GuessAttempt]
    let length: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<length, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: index == attempts.count ? 18 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: attempts.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(attempts.correctCount) correct of \(attempts.count) answered, \(length - attempts.count) to go")
    }

    private func fill(for index: Int) -> Color {
        if index < attempts.count {
            return attempts[index].isCorrect ? .correctTint : .wrongTint
        }
        return index == attempts.count ? Color.primaryText.opacity(0.85) : Color.white.opacity(0.12)
    }
}

/// The center of the wheel during a round: replays the mystery note, then shows the verdict.
struct GameCenterBadge: View {
    let side: CGFloat
    let root: RootNote
    let questionNumber: Int
    let length: Int
    let challenge: IntervalInfo?
    let answer: IntervalInfo?
    let streak: Int
    let playCount: Int
    let action: () -> Void

    private var isCorrect: Bool? {
        guard let challenge, let answer else { return nil }
        return challenge.semitones == answer.semitones
    }

    private var tint: Color {
        switch isCorrect {
        case true?: .correctTint
        case false?: .wrongTint
        case nil: .accentTint
        }
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: 0x17191E))
                .overlay(Circle().fill(tint.opacity(isCorrect == nil ? 0.04 : 0.1)))
                .overlay(Circle().stroke(tint.opacity(isCorrect == nil ? 0.22 : 0.6), lineWidth: 1.5))
                .shadow(color: tint.opacity(isCorrect == nil ? 0 : 0.28), radius: 18)
                .overlay {
                    content
                        .id(isCorrect.map { $0 ? "correct" : "wrong" } ?? "listening")
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        .minimumScaleFactor(0.7)
                        .padding(side * 0.03)
                }
                .frame(width: side * 0.40, height: side * 0.40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .keyboardShortcut(.space, modifiers: [])
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isCorrect)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(answer == nil ? "Plays the mystery note again" : "Skips to the next note")
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: side * 0.012) {
            switch isCorrect {
            case nil:
                eyebrow(challenge == nil ? "GET READY" : "NOTE \(questionNumber) OF \(length)")
                Image(systemName: challenge == nil ? "ear" : "speaker.wave.2.fill")
                    .font(.system(size: side * 0.075, weight: .medium))
                    .foregroundStyle(Color.accentTint)
                    .symbolEffect(.bounce, value: playCount)
                    .padding(.vertical, side * 0.008)
                caption(challenge == nil ? "ABOVE \(root.displayName)" : "TAP TO REPLAY")
            case true?:
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.07, weight: .bold))
                    .foregroundStyle(Color.correctTint)
                Text(challenge?.name ?? "")
                    .font(.system(size: side * 0.036, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                    .multilineTextAlignment(.center)
                if streak >= 2 {
                    Label("\(streak) IN A ROW", systemImage: "flame.fill")
                        .font(.system(size: max(8, side * 0.018), weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Color.streakTint)
                } else {
                    caption("NICE EAR")
                }
            case false?:
                Image(systemName: "xmark")
                    .font(.system(size: side * 0.06, weight: .bold))
                    .foregroundStyle(Color.wrongTint)
                eyebrow("IT WAS")
                Text(challenge?.name ?? "")
                    .font(.system(size: side * 0.036, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                    .multilineTextAlignment(.center)
                caption("TAP TO CONTINUE")
            }
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(8, side * 0.018), weight: .bold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(Color.mutedText)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(7, side * 0.016), weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(Color.secondaryText)
    }

    private var accessibilityText: String {
        guard let challenge else { return "Get ready. The first note is about to play." }
        guard let answer else { return "Note \(questionNumber) of \(length). Replay the mystery note." }
        return answer.semitones == challenge.semitones
            ? "Correct, \(challenge.name)."
            : "Not quite. It was the \(challenge.name.lowercased()); you chose \(answer.name.lowercased())."
    }
}
