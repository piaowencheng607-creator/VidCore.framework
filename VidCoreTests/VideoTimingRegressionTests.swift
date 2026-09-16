import CoreMedia
import XCTest

@testable import VidCore

final class VideoTimingRegressionTests: XCTestCase {
    private actor CollectingRenderer: VideoRendererTarget {
        private(set) var frameCount = 0

        func enqueue(_ frame: VideoFrame) {
            frameCount += 1
        }
    }

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: VideoTimingRegressionTests.self)
        return try XCTUnwrap(
            bundle.url(
                forResource: "quicktime-png-12fps-22frames",
                withExtension: "mov",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "quicktime-png-12fps-22frames",
                withExtension: "mov"
            ),
            "Missing QuickTime/PNG regression fixture"
        )
    }

    func testQuickTimePNGUsesFrameTimelineAndDrainsEveryFrame() async throws {
        let url = try fixtureURL()
        let decoder = try MediaDecoder(url: url, hardwareDecodeMode: .decode)
        defer { decoder.close() }

        var videoFrames: [VideoFrame] = []
        while let packet = await decoder.demuxNextPacket() {
            for case .video(let frame) in await decoder.decodePacket(packet) {
                videoFrames.append(frame)
            }
        }

        await decoder.flushMediaDecoder()
        while let frame = await decoder.drainVideoFrame() {
            videoFrames.append(frame)
        }

        XCTAssertEqual(videoFrames.count, 22)
        XCTAssertEqual(videoFrames[0].presentationTime, 0, accuracy: 0.000_001)
        XCTAssertEqual(videoFrames[1].presentationTime, 1.0 / 12.0, accuracy: 0.000_001)
        XCTAssertEqual(videoFrames[12].presentationTime, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(videoFrames[21].presentationTime, 21.0 / 12.0, accuracy: 0.000_001)

        for frame in videoFrames {
            XCTAssertEqual(frame.duration, 1.0 / 12.0, accuracy: 0.000_001)
            XCTAssertEqual(
                CMTimeGetSeconds(frame.sampleBuffer.duration),
                1.0 / 12.0,
                accuracy: 0.000_001
            )
        }

        let decodedDuration = videoFrames[21].presentationTime + videoFrames[21].duration
        XCTAssertEqual(decodedDuration, 22.0 / 12.0, accuracy: 0.000_001)
        XCTAssertEqual(decoder.videoInfo.duration, 22.0 / 12.0, accuracy: 0.000_001)
    }

    @MainActor
    func testPlayerDoesNotFinishBeforeLastQueuedFrameDuration() async throws {
        let player = MediaPlayer(buffers: .software)
        let renderer = CollectingRenderer()
        await player.setRenderer(renderer)
        try await player.load(url: fixtureURL())
        player.play()

        let clock = ContinuousClock()
        let enqueueDeadline = clock.now + .seconds(2)
        while clock.now < enqueueDeadline {
            if await renderer.frameCount >= 22 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let frameCount = await renderer.frameCount
        XCTAssertEqual(frameCount, 22)
        XCTAssertEqual(player.state, .playing, "EOF must not pause queued frames")

        let finishDeadline = clock.now + .seconds(3)
        while player.state != .finished && clock.now < finishDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(player.state, .finished)
        XCTAssertEqual(player.currentTime, 22.0 / 12.0, accuracy: 0.01)
        await player.close()
    }
}
