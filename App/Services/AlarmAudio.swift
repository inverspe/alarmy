import AVFoundation
import AlarmyCore
import os

/// Plays the alarm tone, and keeps the app alive in the background by running
/// the audio engine (rendering silence) while any alarm is armed.
final class AlarmAudio {
    /// What the render callback plays. A ramp is timed on the monotonic clock, so nothing
    /// that restarts the audio engine can restart the ramp.
    private struct Ring {
        let sound: AlarmSound
        var rampStart: UInt64 = 0
        var rampDuration: TimeInterval = 0

        func level(at time: UInt64) -> Float {
            guard rampDuration > 0 else { return 1 }
            let elapsed = time > rampStart ? Double(time - rampStart) / 1_000_000_000 : 0
            return GentleRamp.level(elapsed: elapsed, duration: rampDuration)
        }
    }

    private var engine = AVAudioEngine()
    private let ring = OSAllocatedUnfairLock<Ring?>(initialState: nil)
    private var keepAlive = false
    private(set) var isRinging = false
    private let log = DiagnosticLog.shared

    /// Session options while ringing. Must stay mixable: iOS refuses to activate an
    /// exclusive (`[]`) session from the background (error 560557684, "cannot interrupt
    /// others"), seen on device in build 19. `.duckOthers` mixes and turns other audio down.
    var ringOptions: AVAudioSession.CategoryOptions = [.duckOthers]

    init() {
        buildGraph()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self?.log.add("audio interruption \(type == .began ? "began" : "ended")")
            if type == .ended { self?.resume() }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.log.add("media services reset")
            self.engine.stop()
            self.engine = AVAudioEngine()
            self.buildGraph()
            self.resume()
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            self?.log.add("engine configuration change")
            self?.resume()
        }
    }

    func startKeepAlive() {
        guard !keepAlive else { return }
        keepAlive = true
        resume()
    }

    func stopKeepAlive() {
        guard keepAlive else { return }
        keepAlive = false
        if !isRinging { shutDown() }
    }

    /// Restarts the engine if something (e.g. another app) stopped it without telling us.
    func ensureRunning() {
        if (keepAlive || isRinging) && !engine.isRunning { resume() }
    }

    /// `gentle` builds up to full volume over `duration` seconds, `elapsed` of which have already passed.
    func startRinging(_ alarmSound: AlarmSound, gentle: (elapsed: TimeInterval, duration: TimeInterval)? = nil) {
        var next = Ring(sound: alarmSound)
        if let gentle {
            let elapsedNanos = UInt64(max(0, gentle.elapsed) * 1_000_000_000)
            let now = clock_gettime_nsec_np(CLOCK_MONOTONIC)
            next.rampStart = now > elapsedNanos ? now - elapsedNanos : 0
            next.rampDuration = gentle.duration
        }
        ring.withLock { [next] in $0 = next }
        isRinging = true
        log.add("start ringing \(alarmSound.rawValue), gentle \(gentle.map { "\(Int($0.elapsed))/\(Int($0.duration)) s" } ?? "off"), options \(ringOptions.rawValue)")
        resume()
    }

    func stopRinging() {
        ring.withLock { $0 = nil }
        isRinging = false
        if keepAlive { resume() } else { shutDown() }
    }

    private func buildGraph() {
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let sampleRate = rate > 0 ? rate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let ring = self.ring
        var t = 0.0
        let step = 1 / sampleRate
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let current = ring.withLock { $0 }
            let level = current?.level(at: clock_gettime_nsec_np(CLOCK_MONOTONIC)) ?? 0
            for frame in 0..<Int(frameCount) {
                let value: Float = current.map { ToneGenerator.sample($0.sound, at: t) * level } ?? 0
                t += step
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
    }

    /// Options only take effect on activation, so a change of options re-activates the session.
    private func resume() {
        guard keepAlive || isRinging else { return }
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = isRinging ? ringOptions : [.mixWithOthers]
        let changing = session.category != .playback || session.categoryOptions != options
        if changing && engine.isRunning {
            engine.stop()
            do { try session.setActive(false) } catch { log.add("deactivate failed: \(describe(error))") }
        }
        do { try session.setCategory(.playback, mode: .default, options: options) } catch {
            log.add("setCategory failed: \(describe(error))")
        }
        do { try session.setActive(true) } catch { log.add("activate failed: \(describe(error))") }
        if !engine.isRunning {
            do { try engine.start() } catch { log.add("engine start failed: \(describe(error))") }
        }
        log.add("resume ringing=\(isRinging) options=\(options.rawValue) otherAudio=\(session.isOtherAudioPlaying) running=\(engine.isRunning)")
    }

    private func shutDown() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        log.add("audio shut down")
    }

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.code) \(ns.localizedDescription)"
    }
}
