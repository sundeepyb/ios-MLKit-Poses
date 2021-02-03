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

final class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: init preview view
    var previewView: UIView!
    
    //MARK: init REST Helper
    var postRequest = APIPostRequest(resource: "https://v3yr6f5rmf.execute-api.us-east-1.amazonaws.com/prod/echo")
    
    var captureSession: AVCaptureSession?
    var frontCamera: AVCaptureDevice?
    var frontCameraInput: AVCaptureDeviceInput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureVideoDataOutput!
    var jointsToTrack: [PoseLandmarkType] = [.leftShoulder,.rightShoulder,.leftHip,.rightHip,.leftKnee,.rightKnee]
    var bodyPositions: [BodyPositionData] = []
    
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
    
    override func viewDidLoad() {
        // MARK: build and add preview view
        previewView = UIView(frame: CGRect(x:0, y:0, width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height))
        previewView.contentMode = UIView.ContentMode.scaleAspectFit
        view.addSubview(previewView)
        prepare {(error) in
            if let error = error {
                print(error)
            }
            try? self.displayPreview(on: self.previewView)
        }
    }
    
    func prepare(completionHandler: @escaping (Error?) -> Void) {
        // MARK: configure PoseDetector from MLKit
        let options = AccuratePoseDetectorOptions()
        options.detectorMode = .stream
        poseDetector = PoseDetector.poseDetector(options: options)
        
        // MARK: initialize capture session
        func createCaptureSession(){
            self.captureSession = AVCaptureSession()
        }
        
        // MARK: configure capture device
        func configureCaptureDevices() throws {
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front)
            self.frontCamera = camera
            try camera?.lockForConfiguration()
            camera?.unlockForConfiguration()
        }
        
        // MARK: configure device inputs
        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
            if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!)}
                else { throw CameraControllerError.inputsAreInvalid }
                
                videoOutput = AVCaptureVideoDataOutput()
                videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)]
                videoOutput.alwaysDiscardsLateVideoFrames = true

                if (captureSession.canAddOutput(videoOutput) == true) {
                captureSession.addOutput(videoOutput)
                }
                
                let queue = DispatchQueue(label: "fr.popigny.videoQueue", attributes: [])
                videoOutput.setSampleBufferDelegate(self, queue: queue)
            }
            else { throw CameraControllerError.noCamerasAvailable }
            captureSession.commitConfiguration()

            captureSession.startRunning()
            
            // Stop after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                self.captureSession?.stopRunning()
                print("Saving to data store")
                self.postRequest.savePositions(positions: self.bodyPositions)
            }
        }
        
        // MARK: call func on bg thread
        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                try configureCaptureDevices()
                try configureDeviceInputs()
            }
            catch {
                DispatchQueue.main.async{
                    completionHandler(error)
                }
                return
            }
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    //MARK: Add video preview to view
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
            
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
//    // MARK: Capture Output
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          print("Failed to get image buffer from sample buffer.")
          return
        }
        let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        let image = VisionImage(buffer: sampleBuffer)
        image.orientation = imageOrientation(
          deviceOrientation: UIDevice.current.orientation,
            cameraPosition: .back)
        var results: [Pose]?
        do {
        results = try self.poseDetector!.results(in: image)
        } catch let error {
          print("Failed to detect pose with error: \(error.localizedDescription).")
          return
        }
        guard let detectedPoses = results, !detectedPoses.isEmpty else {
//
          return
        }
        for pose in detectedPoses {
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
            print("Positions added: \(bodyPositions.count)")
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

//extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
//
//}

// MARK: Make view controller compat with SwiftUI
extension CameraViewController : UIViewControllerRepresentable{
    public typealias UIViewControllerType = CameraViewController
    
    public func makeUIViewController(context: UIViewControllerRepresentableContext<CameraViewController>) -> CameraViewController {
        return CameraViewController()
    }
    
    public func updateUIViewController(_ uiViewController: CameraViewController, context: UIViewControllerRepresentableContext<CameraViewController>) {
    }
}
