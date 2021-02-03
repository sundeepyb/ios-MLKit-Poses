//
//  BodyPositionData.swift
//  ios-pocketExamRoom
//
//  Created by Weintraub, Eric M./Technology Division on 2/1/21.
//

import Foundation

struct BodyPositionData: Codable {
    var timeStamp: Date
    var leftShoulder: JointLocationData?
    var rightShoulder: JointLocationData?
    var leftHip: JointLocationData?
    var rightHip: JointLocationData?
    var leftKnee: JointLocationData?
    var rightKnee: JointLocationData?
}

struct JointLocationData: Codable {
    let jointLocation: [Double]?
    let jointAngle: Double?
}
