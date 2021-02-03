//
//  ContentView.swift
//  ios-pocketExamRoom
//
//  Created by Weintraub, Eric M./Technology Division on 2/1/21.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            CameraViewController()
                .edgesIgnoringSafeArea(.top)
            VStack{
               Spacer()
                HStack(spacing: 150) {
                    Button("Start"){
                        
                    }
                    Button("Stop"){
                        
                    }
                }
                .foregroundColor(Color.white)
            }
            
        }
        .background(Color.black)
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
