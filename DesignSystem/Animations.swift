import SwiftUI

// All animation curves, choreography, and interaction delays live here.
enum Animations {
    static let bouncy = Animation.spring(response: Motion.expandResponse, dampingFraction: 0.62)
    static let snappy = Animation.spring(response: Motion.collapseResponse, dampingFraction: 0.78)
    static let gentle = Animation.spring(response: 0.7, dampingFraction: 0.9)
    static let squash = Animation.easeOut(duration: Motion.pressDuration)
    static let anticipation = Animation.easeOut(duration: Motion.anticipationDuration)
    static let working = Animation.linear(duration: Motion.orbitDuration).repeatForever(autoreverses: false)
    static let particles = Animation.easeOut(duration: Motion.particleDuration)
    static let poof = Animation.easeOut(duration: Motion.poofDuration)
    static let glow = Animation.easeInOut(duration: Motion.glowDuration).repeatForever(autoreverses: true)
    static let bob = Animation.easeInOut(duration: Motion.bobDuration).repeatForever(autoreverses: true)
    static let fade = Animation.easeOut(duration: Motion.fadeDuration)
    static let sendFlight = Animation.easeInOut(duration: Motion.sendFlightDuration)
    static let settingsFade = Animation.easeOut(duration: Motion.settingsFadeDuration)
    static let marchingDashes = Animation.linear(duration: Motion.dashDuration).repeatForever(autoreverses: false)
}

extension Animation {
    static let bouncy = Animations.bouncy
    static let snappy = Animations.snappy
    static let gentle = Animations.gentle
    static let squash = Animations.squash
    static let working = Animations.working
}

enum Motion {
    static let settingsFadeDuration: TimeInterval = 0.15
    static let dashDuration: TimeInterval = 8
    static let sleepyDelay: TimeInterval = 20
    static let linkCelebration: TimeInterval = 1.2
    static let scanSweep: TimeInterval = 0.85
    static let scanCornerBeat: TimeInterval = 0.16
    static let ocrBoxStagger: TimeInterval = 0.025
    static let previewPointerInterval: TimeInterval = 0.1
    static let filmFrameInterval: TimeInterval = 1.0 / 24
    static let filmReelDuration: TimeInterval = 0.8
    static let fadeDuration: TimeInterval = 0.16
    static let permissionCelebration: TimeInterval = 0.8
    static let tourBeat: TimeInterval = 1.15
    static let pressDuration: TimeInterval = 0.12
    static let expandResponse: TimeInterval = 0.45
    static let collapseResponse: TimeInterval = 0.3
    static let anticipationDuration: TimeInterval = 0.06
    static let anticipationScale: CGFloat = 0.98
    static let contentLead: TimeInterval = expandResponse * 0.7
    static let contentStagger: TimeInterval = 0.06
    static let hoverDebounce: TimeInterval = 0.08
    static let hoverWatchdog: TimeInterval = 0.04
    static let collapseDelay: TimeInterval = 0.4
    static let spaceSettle: TimeInterval = 0.2
    static let orbitDuration: TimeInterval = 1.2
    static let frameInterval: TimeInterval = 1.0 / 60
    static let blinkInterval: ClosedRange<TimeInterval> = 3...5
    static let blinkDuration: TimeInterval = 0.12
    static let gulpBeat: TimeInterval = 0.12
    static let cardStagger: TimeInterval = 0.05
    static let particleDuration: TimeInterval = 0.6
    static let poofDuration: TimeInterval = 0.22
    static let glowDuration: TimeInterval = 0.65
    static let bobDuration: TimeInterval = 0.32
    static let minimumJobDuration: TimeInterval = 0.5
    static let sendTileStagger: TimeInterval = 0.045
    static let sendWiggleStep: TimeInterval = 0.08
    static let sendFlightDuration: TimeInterval = 0.6
    static let sendToastDuration: TimeInterval = 2.0
    static let waveStep: TimeInterval = 0.13
}
