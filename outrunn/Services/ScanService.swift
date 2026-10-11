//
//  ScanService.swift
//  outrunn
//
//  Presage SmartSpectra setup. The SDK needs its API key on the device.
//

import AVFoundation
import SmartSpectra

enum ScanService {
    static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "SMARTSPECTRA_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func configure(_ sdk: SmartSpectraSDK) {
        sdk.config.apiKey = apiKey
        sdk.config.cameraPosition = .front
        sdk.config.imageOutputEnabled = true
        sdk.config.requestedMetrics =
            SmartSpectraConfig.breathingMetrics + SmartSpectraConfig.cardioMetrics
    }

    static func ensureCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}
