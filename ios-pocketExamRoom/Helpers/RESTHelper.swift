//
//  RESTHelper.swift
//  ios-pocketExamRoom
//
//  Created by Weintraub, Eric M./Technology Division on 2/1/21.
//

import Foundation

struct PoseData: Codable {
    var source: String
    var positions: [BodyPositionData]
}

struct APIPostRequest {
    var request: URLRequest
//    var poseData: [String : Any] = ["source":"MLKit","positions": []]
    var responseString = ""
    
    init(resource _url: String){
        let url = URL(string: _url)!
        request = URLRequest(url:url)
        
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    
    mutating func savePositions(positions: [BodyPositionData]) {
        let thisPoseData = PoseData(source: "MLKit", positions: positions)
//        let bodyData = try? JSONSerialization.data(withJSONObject: thisPoseData, options: [])
        let bodyData = try? JSONEncoder().encode(thisPoseData)
        print(String(data: bodyData!, encoding: .utf8)!)
//        request.httpBody = bodyData
//        let session = URLSession.shared
//        let task = session.dataTask(with: request) { (data, response, error) in
//            if let error = error {
//                // Handle HTTP request error
//                print("Error posting data: \(error)")
//            } else if let data = data {
//                // Handle HTTP request response
//                print("Data posted: \(String(data: data, encoding: String.Encoding.utf8)!)")
//            } else {
//                // Handle unexpected error
//                print("Error posting data: Unexpected Error")
//            }
//        }
//        task.resume()
    }
}
