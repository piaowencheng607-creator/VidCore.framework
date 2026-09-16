//
//  MediaDecoder+Helpers.swift
//  VidCore
//

import CoreVideo
import Foundation

extension MediaDecoder {
    func makeVideoFrame(
        pixelBuffer: CVPixelBuffer,
        presentationTime: Double,
        duration: Double = 0,
        doviProfile: Int,
        ambientLightMetadata: Data?
    ) -> VideoFrame? {
        return VideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTime: presentationTime,
            duration: duration,
            isHDR: self.videoInfo.isHDR,
            colorTransfer: self.videoInfo.colorTransfer,
            doviProfile: doviProfile,
            ambientLightMetadata: ambientLightMetadata
        )
    }
}
