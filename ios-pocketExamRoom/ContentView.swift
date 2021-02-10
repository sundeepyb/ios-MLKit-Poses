//
//  ContentView.swift
//  ios-pocketExamRoom
//
//  Created by Mounika Gandavarapu on 2/7/21.
//

import SwiftUI

struct ContentView: View {
    let cameraView = CameraViewController()
    @ObservedObject var examTimer = ExamTimer()
    
    var body: some View {
        ZStack {
            cameraView
                .edgesIgnoringSafeArea(.top)
            VStack{
                HStack {
                    Spacer()
                    Button(action: {
                        self.cameraView.switchCamera("SwitchButton")
                    }) {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 32.0))
                            .padding(.trailing, 8)
                    }
                }
                Spacer()
                VStack {
                   Spacer()
                    Text(examTimer.statusMessage)
                    HStack(spacing: 150) {
                        Button(action: {
                            examTimer.prepare()
                            // self.cameraView.startAction()
                        }) {
                            Text(examTimer.status == "init" ? "Start" : "\(examTimer.counter)")
                        }
                        .padding()
                        .frame(width: 85 , height: 85, alignment: .center)
                        .font(.system(size: 22))
                        .background(examTimer.status == "start" ? Color(UIColor(red: 0.95, green: 0.40, blue: 0.16, alpha: 1.00)) : Color(UIColor(red: 0.0392, green: 0.4078, blue: 0.7647, alpha: 1.0)))
                        .foregroundColor(Color.white)
                        .clipShape(Circle())
                        .shadow(radius: 8)
                    }
                    .foregroundColor(Color.white)
                }
            }
        }
        .background(Color.black)
    }
}

class ExamTimer: ObservableObject {
    @Published var counter: Int = 0
    @Published var status: String = "init" //"init", "prepare", "start"
    @Published var statusMessage: String = ""
    
    var timer = Timer()
    
    func prepare() {
        if (self.counter != 0) {
            return
        }
        self.counter = 5
        self.status = "prepare"
        self.statusMessage = "Exam will start in 5 seconds"
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.counter -= 1
            if (self.counter == 0) {
                self.stop()
                self.start()
            }
        }
    }
    
    func start() {
        self.counter = 30
        self.status = "start"
        self.statusMessage = "Examining"
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.counter -= 1
            if (self.counter == 0) {
                self.stop()
                self.status = "init"
            }
        }
    }
    
    func stop() {
        timer.invalidate()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
