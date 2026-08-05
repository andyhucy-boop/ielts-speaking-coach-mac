import IELTSCoachUI
import SwiftUI

struct CoachApp: App {
    var body: some Scene {
        WindowGroup("IELTS Speaking Coach") { RootView() }
            .defaultSize(width: 1100, height: 720)
    }
}

CoachApp.main()
