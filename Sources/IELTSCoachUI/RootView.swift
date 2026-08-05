import SwiftUI

public struct RootView: View {
    public init() {}

    public var body: some View {
        Text("IELTS Speaking Coach")
            .font(.title)
            .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview { RootView() }
