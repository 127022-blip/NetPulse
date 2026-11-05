import SwiftUI
import AppKit

struct AboutView: View {
    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? Constants.App.version
    }

    private var buildText: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build ?? Constants.App.build
    }

    /// Prefer the running app icon; fall back to named application icon or empty image.
    private var appIcon: NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 0 {
            return icon
        }
        if let named = NSImage(named: NSImage.applicationIconName) {
            return named
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let fromFile = NSImage(contentsOfFile: path) {
            return fromFile
        }
        return NSImage(size: NSSize(width: 64, height: 64))
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 6)

            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)

            Text("NetPulse")
                .font(.system(size: 22, weight: .bold))

            VStack(spacing: 4) {
                Text("版本 \(versionText) (\(buildText))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text("Copyright © 2026 GengLei")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 6)
        }
        .frame(width: 300, height: 200)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
