import AppKit
import Observation

@MainActor
@Observable
final class LogoAnimator {
    private(set) var currentImage: NSImage
    private(set) var isAnimating = false
    @ObservationIgnored var onFrameChanged: ((NSImage) -> Void)?

    @ObservationIgnored private let targetSize: CGSize
    @ObservationIgnored private var animations: LogoAnimations?
    @ObservationIgnored private var didAttemptLoad = false
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var alwaysAnimate = false
    @ObservationIgnored private var animationsEnabled = true
    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var frameIndex = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var stopAfterTransitionIn = false
    @ObservationIgnored private var startAfterTransitionOut = false

    private enum Phase {
        case idle
        case transitionIn
        case running
        case transitionOut
    }

    init(targetSize: CGSize = CGSize(width: 28, height: 16)) {
        self.targetSize = targetSize
        currentImage = Self.fallbackImage(size: targetSize)
    }

    func setScanning(_ scanning: Bool) {
        guard isScanning != scanning else { return }
        isScanning = scanning
        updateDesiredState()
    }

    func setAlwaysAnimate(_ enabled: Bool) {
        guard alwaysAnimate != enabled else { return }
        alwaysAnimate = enabled
        updateDesiredState()
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        guard animationsEnabled != enabled else { return }
        animationsEnabled = enabled
        if enabled {
            updateDesiredState()
        } else {
            stopImmediately()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
        phase = .idle
        frameIndex = 0
        stopAfterTransitionIn = false
        startAfterTransitionOut = false
    }

    private var desiredRunning: Bool {
        animationsEnabled && (isScanning || alwaysAnimate)
    }

    private func stopImmediately() {
        stopAfterTransitionIn = false
        startAfterTransitionOut = false
        phase = .idle
        frameIndex = 0
        if let idle = animations?.idle {
            show(idle)
        }
        stopTimer()
    }

    private func updateDesiredState() {
        if desiredRunning {
            stopAfterTransitionIn = false
            switch phase {
            case .idle:
                startTransitionIn()
            case .transitionOut:
                startAfterTransitionOut = true
            case .transitionIn, .running:
                break
            }
        } else {
            startAfterTransitionOut = false
            switch phase {
            case .transitionIn:
                stopAfterTransitionIn = true
            case .running:
                startTransitionOut()
            case .transitionOut, .idle:
                break
            }
        }
    }

    private func startTransitionIn() {
        guard ensureAnimationsLoaded(), let animations, !animations.idleToRun.isEmpty else { return }
        phase = .transitionIn
        frameIndex = 0
        show(animations.idleToRun[0])
        startTimer()
    }

    private func startTransitionOut() {
        guard ensureAnimationsLoaded(), let animations, !animations.runToIdle.isEmpty else {
            phase = .idle
            stopTimer()
            return
        }
        phase = .transitionOut
        frameIndex = 0
        show(animations.runToIdle[0])
        startTimer()
    }

    private func finishTransitionOut() {
        phase = .idle
        frameIndex = 0
        if let idle = animations?.idle {
            show(idle)
        }
        stopTimer()
        if startAfterTransitionOut {
            startAfterTransitionOut = false
            startTransitionIn()
        }
    }

    private func advanceFrame() {
        guard let animations else {
            stopTimer()
            return
        }

        switch phase {
        case .idle:
            stopTimer()

        case .transitionIn:
            guard !animations.idleToRun.isEmpty else {
                phase = .idle
                stopTimer()
                return
            }
            frameIndex += 1
            if frameIndex >= animations.idleToRun.count {
                if stopAfterTransitionIn {
                    stopAfterTransitionIn = false
                    startTransitionOut()
                } else {
                    phase = .running
                    frameIndex = 0
                    if let first = animations.run.first {
                        show(first)
                    }
                }
            } else {
                show(animations.idleToRun[frameIndex])
            }

        case .running:
            guard !animations.run.isEmpty else {
                phase = .idle
                stopTimer()
                return
            }
            frameIndex = (frameIndex + 1) % animations.run.count
            show(animations.run[frameIndex])

        case .transitionOut:
            guard !animations.runToIdle.isEmpty else {
                finishTransitionOut()
                return
            }
            frameIndex += 1
            if frameIndex >= animations.runToIdle.count {
                finishTransitionOut()
            } else {
                show(animations.runToIdle[frameIndex])
            }
        }
    }

    @discardableResult
    private func ensureAnimationsLoaded() -> Bool {
        if animations != nil {
            return true
        }
        if didAttemptLoad {
            return false
        }
        didAttemptLoad = true
        animations = LogoAnimations.load(targetSize: targetSize)
        if let idle = animations?.idle {
            show(idle)
        }
        return animations != nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        isAnimating = true
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
    }

    private func show(_ image: NSImage) {
        guard currentImage !== image else { return }
        currentImage = image
        onFrameChanged?(image)
    }

    private static func fallbackImage(size: CGSize) -> NSImage {
        let url = Bundle.main.url(forResource: "MustelMenuBar", withExtension: "png")
            ?? Bundle.module.url(forResource: "MustelMenuBar", withExtension: "png")
        if let url, let image = NSImage(contentsOf: url) {
            image.size = size
            image.isTemplate = true
            return image
        }
        let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Mustel")
            ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        return image
    }
}

private struct LogoAnimations {
    let idleToRun: [NSImage]
    let run: [NSImage]
    let runToIdle: [NSImage]
    let idle: NSImage

    static func load(targetSize: CGSize) -> LogoAnimations? {
        guard targetSize.width > 0, targetSize.height > 0,
              let idleToRunAnimation = LottieAnimation.named("idle-to-run"),
              let runAnimation = LottieAnimation.named("run"),
              let runToIdleAnimation = LottieAnimation.named("run-to-idle") else {
            return nil
        }

        let bounds = [idleToRunAnimation, runAnimation, runToIdleAnimation]
            .map(\.contentBounds)
            .reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let cropRect = cropRect(for: bounds, aspectRatio: targetSize.width / targetSize.height)
        let idleToRun = idleToRunAnimation.renderFrames(cropRect: cropRect, size: targetSize)
        let run = runAnimation.renderFrames(cropRect: cropRect, size: targetSize)
        let runToIdle = runToIdleAnimation.renderFrames(cropRect: cropRect, size: targetSize)
        guard let idle = idleToRun.first ?? runToIdle.last else { return nil }

        return LogoAnimations(
            idleToRun: idleToRun,
            run: run,
            runToIdle: runToIdle,
            idle: idle
        )
    }

    private static func cropRect(for bounds: CGRect, aspectRatio: CGFloat) -> CGRect {
        let padding = max(bounds.width, bounds.height) * 0.02
        var rect = bounds.insetBy(dx: -padding, dy: -padding)
        if rect.width / rect.height < aspectRatio {
            let width = rect.height * aspectRatio
            rect = rect.insetBy(dx: -(width - rect.width) / 2, dy: 0)
        } else {
            let height = rect.width / aspectRatio
            rect = rect.insetBy(dx: 0, dy: -(height - rect.height) / 2)
        }
        return rect
    }
}
