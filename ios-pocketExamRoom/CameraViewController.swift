//
//  CameraViewController.swift
//  ios-pocketExamRoom
//
//  Created by Weintraub, Eric M./Technology Division on 2/1/21.
//

import Foundation
import UIKit
import SwiftUI
import AVFoundation
import MLKit

@objc(CameraViewController)
final class CameraViewController: UIViewController {

    // MARK: init preview view
    @IBOutlet private var previewView: UIView!
    
    //MARK: init REST Helper
    var postRequest = APIPostRequest(resource: "https://v3yr6f5rmf.execute-api.us-east-1.amazonaws.com/prod/echo")
    
    lazy var captureSession = AVCaptureSession()
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var previewLayer: AVCaptureVideoPreviewLayer!
    var videoOutput: AVCaptureVideoDataOutput!
    var jointsToTrack: [PoseLandmarkType] = [.leftShoulder,.rightShoulder,.leftHip,.rightHip,.leftKnee,.rightKnee]
    var bodyPositions: [BodyPositionData] = []
    var lastFrame: CMSampleBuffer?
    var isUsingFrontCamera = true
    lazy var sessionQueue = DispatchQueue(label: Constant.sessionQueueLabel)
    
    var _assetWriter: AVAssetWriter?
    var _assetWriterInput: AVAssetWriterInput?
    var _adpater: AVAssetWriterInputPixelBufferAdaptor?
    var _filename = ""
    var _time: Double = 0
    var _captureState = "idle"
    var timestamp = CFAbsoluteTimeGetCurrent()

    
    // MARK: init Pose Detector
    var poseDetector: PoseDetector?
    
    enum CameraControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    lazy var annotationOverlayView: UIView = {
      let annotationOverlayView = UIView(frame: .zero)
        annotationOverlayView.contentMode = UIView.ContentMode.scaleAspectFill
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        annotationOverlayView.clipsToBounds = true
      return annotationOverlayView
    }()
    
    lazy var previewOverlayView: UIImageView = {
      let previewOverlayView = UIImageView(frame: .zero)
        previewOverlayView.contentMode = UIView.ContentMode.scaleAspectFill
      previewOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return previewOverlayView
    }()
    
    override func viewDidLoad() {
        // MARK: build and add preview view
        super.viewDidLoad()
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        setUpPreviewOverlayView()
        setUpAnnotationOverlayView()
        setUpCaptureSessionOutput()
        setUpCaptureSessionInput()
//        previewView = UIView(frame: CGRect(x:0, y:0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
//        previewView.contentMode = UIView.ContentMode.scaleAspectFill
//        view.addSubview(previewView)
        
        // MARK: configure PoseDetector from MLKit
        let options = AccuratePoseDetectorOptions()
        options.detectorMode = .stream
        poseDetector = PoseDetector.poseDetector(options: options)
        
//        prepare {(error) in
//            if let error = error {
//                print(error)
//            }
//            try? self.displayPreview(on: self.previewOverlayView)
//        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.startSession()
                    }
                }
            case .restricted:
                break
            case .denied:
                break
            case .authorized:
                startSession()
        }
        
        // Stop after 30 seconds
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
//            print("5 seconds timer finished")
//            self.stopSession()
//        }
    }

    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)

      stopSession()
    }
    
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
        if previewLayer != nil {
            previewLayer.frame = view.frame
        }
    }
    
    private func startSession() {
      sessionQueue.async {
        print("captureSession startRunning")
        self.captureSession.startRunning()
      }
    }

    private func stopSession() {
      sessionQueue.async {
        
//        print("stopSession for record file")
//        guard self._assetWriterInput?.isReadyForMoreMediaData == true, self._assetWriter!.status != .failed else { return }
//        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(self._filename).mov")
//        self._assetWriterInput?.markAsFinished()
//        self._assetWriter?.finishWriting { [weak self] in
//            self?._captureState = "idle"
//            self?._assetWriter = nil
//            self?._assetWriterInput = nil
//            DispatchQueue.main.async {
//                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
//                self?.present(activity, animated: true, completion: nil)
//            }
//        }
//
//
        self.captureSession.stopRunning()
      }
    }
    
    public func stopRecording() {
//        self.movieOutput.stopRecording()
    }
    
    private func setUpPreviewOverlayView() {
        if view != nil {
        view.addSubview(previewOverlayView)
          NSLayoutConstraint.activate([
            previewOverlayView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewOverlayView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            previewOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

          ])
        }
    }

    private func setUpAnnotationOverlayView() {
        if view != nil {
            view.addSubview(annotationOverlayView)
          NSLayoutConstraint.activate([
            annotationOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
            annotationOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            annotationOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            annotationOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
          ])
        }
    }
    
    private func normalizedPoint(
      fromVisionPoint point: VisionPoint,
      width: CGFloat,
      height: CGFloat
    ) -> CGPoint {
      let cgPoint = CGPoint(x: point.x, y: point.y)
      let normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
        
    return previewLayer?.layerPointConverted(fromCaptureDevicePoint: normalizedPoint) ?? normalizedPoint
    }
    
    private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
      if #available(iOS 10.0, *) {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: position)
      }
      return nil
    }
    
    private func setUpCaptureSessionInput() {
      sessionQueue.async {
        let cameraPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .front : .back
        guard let device = self.captureDevice(forPosition: cameraPosition) else {
          print("Failed to get capture device for camera position: \(cameraPosition)")
          return
        }
        do {
            self.captureSession.beginConfiguration()
            let currentInputs = self.captureSession.inputs
          for input in currentInputs {
            self.captureSession.removeInput(input)
          }

          let input = try AVCaptureDeviceInput(device: device)
            guard self.captureSession.canAddInput(input) else {
            print("Failed to add capture session input.")
            return
          }
            self.captureSession.addInput(input)
            self.captureSession.commitConfiguration()
        } catch {
          print("Failed to create capture device input: \(error.localizedDescription)")
        }
      }
    }
    
    private func setUpCaptureSessionOutput() {
      sessionQueue.async {
        self.captureSession.beginConfiguration()
        // When performing latency tests to determine ideal capture settings,
        // run the app in 'release' mode to get accurate performance metrics
        self.captureSession.sessionPreset = AVCaptureSession.Preset.medium

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
          (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        let outputQueue = DispatchQueue(label: Constant.videoDataOutputQueueLabel)
        output.setSampleBufferDelegate(self, queue: outputQueue)
        
        
        print("captureOutput start")
        self._filename = UUID().uuidString
        let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(self._filename).mov")
        let writer = try! AVAssetWriter(outputURL: videoPath, fileType: .mov)
        // let settings = output.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        let input = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
                                       AVVideoCodecKey : AVVideoCodecType.h264,
                                       AVVideoWidthKey : 720,
                                       AVVideoHeightKey : 1280,
                                       AVVideoCompressionPropertiesKey : [
                                           AVVideoAverageBitRateKey : 2300000,
                                           ],
                                       ]) // [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080])
        input.expectsMediaDataInRealTime = true
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        if writer.canAdd(input) {
            writer.add(input)
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        self._assetWriter = writer
        self._assetWriterInput = input
        self._adpater = adapter
        self._captureState = "capturing"
        self._time = self.timestamp

        
        guard self.captureSession.canAddOutput(output) else {
          print("Failed to add capture session output.")
          return
        }
        self.captureSession.addOutput(output)
        self.captureSession.commitConfiguration()
      }
    }
    
    @IBAction func switchCamera(_ sender: Any) {
      isUsingFrontCamera = !isUsingFrontCamera
      removeDetectionAnnotations()
      setUpCaptureSessionInput()
    }
    
    @IBAction func startAction() {
      
    }
    
    func removeDetectionAnnotations() {
        for annotationView in self.annotationOverlayView.subviews {
        annotationView.removeFromSuperview()
      }
    }
    public func updateCaptureState() {
        sessionQueue.async {
            if (self._captureState == "idle") {
                self._captureState = "start"
            } else if (self._captureState == "capturing") {
                self._captureState = "end"
            } else {
                print("last else")
                print(self._captureState)
            }
        }
    }
    
    @IBAction public func capture(_ sender: Any) {
        print("capture function triggered")
        updateCaptureState()
    }
        
    private func updatePreviewOverlayView() {
      guard let lastFrame = lastFrame,
        let imageBuffer = CMSampleBufferGetImageBuffer(lastFrame)
      else {
        return
      }
      let ciImage = CIImage(cvPixelBuffer: imageBuffer)
      let context = CIContext(options: nil)
      guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        return
      }
      let rotatedImage = UIImage(cgImage: cgImage, scale: Constant.originalScale, orientation: .right)
      if isUsingFrontCamera {
        guard let rotatedCGImage = rotatedImage.cgImage else {
          return
        }
        let mirroredImage = UIImage(
          cgImage: rotatedCGImage, scale: Constant.originalScale, orientation: .leftMirrored)
        previewOverlayView.image = mirroredImage
      } else {
        previewOverlayView.image = rotatedImage
      }
    }

    // MARK: get image orientation
    func imageOrientation(
      deviceOrientation: UIDeviceOrientation,
      cameraPosition: AVCaptureDevice.Position
    ) -> UIImage.Orientation {
      switch deviceOrientation {
      case .portrait:
        return cameraPosition == .front ? .leftMirrored : .right
      case .landscapeLeft:
        return cameraPosition == .front ? .downMirrored : .up
      case .portraitUpsideDown:
        return cameraPosition == .front ? .rightMirrored : .left
      case .landscapeRight:
        return cameraPosition == .front ? .upMirrored : .down
      case .faceDown, .faceUp, .unknown:
        return .upMirrored
      @unknown default:
        return .upMirrored
      }
    }
    
    // MARK: Caluclate angle
    func angle(
          firstLandmark: PoseLandmark,
          midLandmark: PoseLandmark,
          lastLandmark: PoseLandmark
      ) -> CGFloat {
          let radians: CGFloat =
              atan2(lastLandmark.position.y - midLandmark.position.y,
                        lastLandmark.position.x - midLandmark.position.x) -
                atan2(firstLandmark.position.y - midLandmark.position.y,
                        firstLandmark.position.x - midLandmark.position.x)
          var degrees = radians * 180.0 / .pi
          degrees = abs(degrees) // Angle should never be negative
          if degrees > 180.0 {
              degrees = 360.0 - degrees // Always get the acute representation of the angle
          }
          return degrees
      }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: Capture Output
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

//        timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
//        if (_captureState == "capturing") {
//            print("captureOutput capturing")
//            if _assetWriterInput?.isReadyForMoreMediaData == true {
//                let time = CMTime(seconds: timestamp - _time, preferredTimescale: CMTimeScale(600))
//                _adpater?.append(CMSampleBufferGetImageBuffer(sampleBuffer)!, withPresentationTime: time)
//            }
//        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          print("Failed to get image buffer from sample buffer.")
          return
        }
        let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        let image = VisionImage(buffer: sampleBuffer)
        lastFrame = sampleBuffer
        image.orientation = imageOrientation(
          deviceOrientation: UIDevice.current.orientation,
            cameraPosition: .back)
        if let poseDetector = self.poseDetector {
            var poses: [Pose]
            do {
                poses = try poseDetector.results(in: image)
            } catch let error {
              print("Failed to detect pose with error: \(error.localizedDescription).")
              return
            }
            guard !poses.isEmpty else {
              print("Pose detector returned no results.")
              return
            }
            DispatchQueue.main.sync {
              self.updatePreviewOverlayView()
              self.removeDetectionAnnotations()
            }
            DispatchQueue.main.sync {
                poses.forEach { pose in
                  let poseOverlayView = UIUtilities.createPoseOverlayView(
                    forPose: pose,
                    inViewWithBounds: self.annotationOverlayView.bounds,
                    lineWidth: Constant.lineWidth,
                    dotRadius: Constant.smallDotRadius,
                    positionTransformationClosure: { (position) -> CGPoint in
                      return self.normalizedPoint(fromVisionPoint: position, width: width,
                                                        height: height)
                    }
                  )
                  self.annotationOverlayView.addSubview(poseOverlayView)
                }
            }
            for pose in poses {
                //TODO: Holy hardcoded
                let leftShoulderLandmark = pose.landmark(ofType: .leftShoulder)
                let leftShoulderAngle = angle(firstLandmark: pose.landmark(ofType: .leftElbow), midLandmark: pose.landmark(ofType: .leftShoulder), lastLandmark: pose.landmark(ofType: .leftHip))
                let leftShoulder = JointLocationData(jointLocation: [Double(leftShoulderLandmark.position.x),Double(leftShoulderLandmark.position.y)], jointAngle: Double(leftShoulderAngle))
                
                let rightShoulderLandmark = pose.landmark(ofType: .rightShoulder)
                let rightShoulderAngle = angle(firstLandmark: pose.landmark(ofType: .rightElbow), midLandmark: pose.landmark(ofType: .rightShoulder), lastLandmark: pose.landmark(ofType: .rightHip))
                let rightShoulder = JointLocationData(jointLocation: [Double(rightShoulderLandmark.position.x),Double(rightShoulderLandmark.position.y)], jointAngle: Double(rightShoulderAngle))
                
                let leftHipLandmark = pose.landmark(ofType: .leftHip)
                let leftHipAngle = angle(firstLandmark: pose.landmark(ofType: .leftShoulder), midLandmark: pose.landmark(ofType: .leftHip), lastLandmark: pose.landmark(ofType: .leftKnee))
                let leftHip = JointLocationData(jointLocation: [Double(leftHipLandmark.position.x),Double(leftHipLandmark.position.y)], jointAngle: Double(leftHipAngle))
                
                let rightHipLandmark = pose.landmark(ofType: .rightHip)
                let rightHipAngle = angle(firstLandmark: pose.landmark(ofType: .rightShoulder), midLandmark: pose.landmark(ofType: .rightHip), lastLandmark: pose.landmark(ofType: .rightKnee))
                let rightHip = JointLocationData(jointLocation: [Double(rightHipLandmark.position.x),Double(rightHipLandmark.position.y)], jointAngle: Double(rightHipAngle))
                
                let leftKneeLandmark = pose.landmark(ofType: .leftKnee)
                let leftKneeAngle = angle(firstLandmark: pose.landmark(ofType: .leftHip), midLandmark: pose.landmark(ofType: .leftKnee), lastLandmark: pose.landmark(ofType: .leftAnkle))
                let leftKnee = JointLocationData(jointLocation: [Double(leftKneeLandmark.position.x),Double(leftKneeLandmark.position.y)], jointAngle: Double(leftKneeAngle))
                
                let rightKneeLandmark = pose.landmark(ofType: .rightKnee)
                let rightKneeAngle = angle(firstLandmark: pose.landmark(ofType: .rightHip), midLandmark: pose.landmark(ofType: .rightKnee), lastLandmark: pose.landmark(ofType: .rightAnkle))
                let rightKnee = JointLocationData(jointLocation: [Double(rightKneeLandmark.position.x),Double(rightKneeLandmark.position.y)], jointAngle: Double(rightKneeAngle))
                
                let bodyPosition = BodyPositionData(timeStamp: Date(), leftShoulder: leftShoulder, rightShoulder: rightShoulder, leftHip: leftHip, rightHip: rightHip, leftKnee: leftKnee, rightKnee: rightKnee)
                
                bodyPositions.append(bodyPosition)
                print("Left x:\(leftShoulderLandmark.position.x) y:\(leftShoulderLandmark.position.y) Right x:\(rightShoulderLandmark.position.x) y:\(rightShoulderLandmark.position.y)")
            }
        }
    }

}

// MARK: Make view controller compat with SwiftUI
extension CameraViewController : UIViewControllerRepresentable{
    public typealias UIViewControllerType = CameraViewController
    
    public func makeUIViewController(context: UIViewControllerRepresentableContext<CameraViewController>) -> CameraViewController {
        return CameraViewController()
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: UIViewControllerRepresentableContext<CameraViewController>) {
    }
}

private enum Constant {
  static let videoDataOutputQueueLabel = "com.google.mlkit.visiondetector.VideoDataOutputQueue"
  static let sessionQueueLabel = "com.google.mlkit.visiondetector.SessionQueue"
  static let noResultsMessage = "No Results"
  static let labelConfidenceThreshold = 0.75
  static let smallDotRadius: CGFloat = 12.0
  static let lineWidth: CGFloat = 3.0
  static let originalScale: CGFloat = 1.0
  static let padding: CGFloat = 10.0
}
