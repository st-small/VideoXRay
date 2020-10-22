//
//  ViewController.swift
//  VideoXRay
//
//  Created by Stanly Shiyanovskiy on 21.10.2020.
//

import AVKit
import UIKit

public enum SetupError: Error {
    case noVideoDevice, videoInputFailed, videoOutputFailed
}

class ViewController: UIViewController {
    
    // MARK: - Data
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var capturePreview = CapturePreviewView()
    
    private var assetWriter: AVAssetWriter!
    private var writerInput: AVAssetWriterInput!

    private let model = SqueezeNet()
    private let context = CIContext()
    
    private var recordingActive = false
    private var readyToAnalyze = true
    private var startTime: CMTime!
    private var movieURL: URL!
    
    private var predictions = [(time: CMTime, prediction: String)]()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        capturePreview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(capturePreview)

        capturePreview.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        capturePreview.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        capturePreview.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        capturePreview.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        (capturePreview.layer as! AVCaptureVideoPreviewLayer).session = session

        do {
            try configureSession()
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Record", style: .plain, target: self, action: #selector(startRecording))
        } catch {
            print("Session configuration failed!")
        }
    }
    
    private func configureSession() throws {
        session.beginConfiguration()
        try configureVideoDeviceInput()
        try configureVideoDeviceOutput()
        try configureMovieWriting()
        session.commitConfiguration()
    }

    private func configureVideoDeviceInput() throws {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            throw SetupError.noVideoDevice
        }

        let videoDeviceInput = try AVCaptureDeviceInput(device: videoCaptureDevice)

        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
        } else {
            throw SetupError.videoInputFailed
        }
    }

    private func configureVideoDeviceOutput() throws {
        if session.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
            session.addOutput(videoOutput)

            // force portrait recording!
            for connection in videoOutput.connections {
                for port in connection.inputPorts {
                    if port.mediaType == .video {
                        connection.videoOrientation = .portrait
                    }
                }
            }
        } else {
            throw SetupError.videoOutputFailed
        }
    }
    
    private func configureMovieWriting() throws {
        movieURL = getDocumentsDirectory().appendingPathComponent("movie.mov")
        let fm = FileManager.default

        if fm.fileExists(atPath: movieURL.path) {
            try fm.removeItem(at: movieURL)
        }

        assetWriter = try AVAssetWriter(url: movieURL, fileType: .mp4)
        let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)
        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = true

        if assetWriter.canAdd(writerInput) {
            assetWriter.add(writerInput)
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    // MARK: - Actions
    @objc
    private func startRecording() {
        recordingActive = true
        session.startRunning()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Stop", style: .plain, target: self, action: #selector(stopRecording))
    }

    @objc
    private func stopRecording() {
        recordingActive = false
        writerInput.markAsFinished()

        assetWriter?.finishWriting {
            if (self.assetWriter?.status == .failed) {
                print("Creating movie file is failed.")
            } else {
                print("Creating movie file was a success.")

                DispatchQueue.main.async {
                    let results = ResultsViewController(style: .plain)
                    results.movieURL = self.movieURL
                    results.predictions = self.predictions
                    self.navigationController?.pushViewController(results, animated: true)
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recordingActive else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) == true else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if assetWriter.status == .unknown {
            startTime = currentTime
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: currentTime)
            return
        }

        if assetWriter.status == .writing  {
            if writerInput.isReadyForMoreMediaData {
                writerInput.append(sampleBuffer)
            }
        }

        guard readyToAnalyze else { return }
        readyToAnalyze = false

        DispatchQueue.global().async {
            let inputSize = CGSize(width: 227.0, height: 227.0)
            let image = CIImage(cvImageBuffer: pixelBuffer)

            guard let resizedPixelBuffer = image.pixelBuffer(at: inputSize, context: self.context) else { return }
            let prediction = try? self.model.prediction(image: resizedPixelBuffer)
            let predictionName = prediction?.classLabel ?? "Unknown"

            print("\(self.predictions.count): \(predictionName)")
            let timeDiff = currentTime - self.startTime
            self.predictions.append((timeDiff, predictionName))
            self.readyToAnalyze = true
        }
    }
}

extension CIImage {
    func pixelBuffer(at size: CGSize, context: CIContext) -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, attributes, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }

        let scale = size.width / self.extent.size.width
        let resizedImage = self.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let width = resizedImage.extent.width
        let height = resizedImage.extent.height
        let yOffset = (CGFloat(height) - size.height) / 2.0
        let rect = CGRect(x: (CGFloat(width) - size.width) / 2.0, y: yOffset, width: size.width, height: size.height)
        let croppedImage = resizedImage.cropped(to: rect)
        let translatedImage = croppedImage.transformed(by: CGAffineTransform(translationX: 0, y: -yOffset))

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        context.render(translatedImage, to: pixelBuffer!)
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }
}
