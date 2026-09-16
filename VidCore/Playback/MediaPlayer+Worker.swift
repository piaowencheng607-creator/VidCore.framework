//
//  MediaPlayer+Worker.swift
//  VidCore
//

import Foundation

// MARK: - Playback Worker Delegate

extension MediaPlayer: PlaybackWorkerDelegate {
    func workerDidRenderVideoFrame(_ frame: VideoFrame) {
        if pendingPlay {
            pendingPlay = false
            Task {
                await playbackClock.play(rate: playbackRate)
            }
        }
        currentFrame = frame
        // Ensure we are playing if we were stalled
        if state == .playing && playbackClock.rate == 0 {
            Task { await playbackClock.setRate(playbackRate) }
        }
    }

    func workerDidDecodeSubtitle(_ subtitle: SubtitleFrame) {
        subtitles.append(subtitle)
        // Keep only recent subtitles (e.g. last 100)
        if subtitles.count > 100 {
            subtitles.removeFirst()
        }
    }

    func workerDidDetectAudio() {
        hasAudio = true
        // If audio-only or audio starts first
        if pendingPlay {
            pendingPlay = false
            Task {
                await playbackClock.play(rate: playbackRate)
            }
        }
    }

    func workerDidFinishStream(at endTime: Double) {
        guard state == .playing else { return }

        finishTask?.cancel()
        let targetEndTime = endTime > 0 ? endTime : duration
        finishTask = Task { [weak self] in
            guard let self else { return }

            // The packet queue can briefly report a stall just before EOF. Resume
            // the clock so already-enqueued tail frames can still be presented.
            if playbackClock.rate == 0 {
                await playbackClock.setRate(playbackRate)
            }

            while !Task.isCancelled && state == .playing {
                let clockTime = await playbackClock.getCurrentTime()
                if clockTime >= targetEndTime - 0.001 {
                    break
                }
                try? await Task.sleep(for: .milliseconds(10))
            }

            guard !Task.isCancelled, state == .playing else { return }
            currentTime = targetEndTime
            state = .finished
            stopTimeUpdates()
            await playbackClock.pause()
            await audioOutput.flush()
            finishTask = nil
        }
    }

    func workerDidStall() {
        guard state == .playing else { return }
        Task { await playbackClock.setRate(0.0) }
    }

    func workerDidUnstall() {
        guard state == .playing else { return }
        Task { await playbackClock.setRate(playbackRate) }
    }

    func workerRefreshDebugStats(videoPTS: Double?) async {
        await refreshDebugStats(videoPTS: videoPTS)
    }
}
