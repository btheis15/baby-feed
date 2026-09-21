import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The invite, shown three ways because handing someone a log at 3 a.m. should
/// work whichever one is easiest right then:
///
/// - a QR code the other phone reads with the ordinary Camera app (no scanner
///   in this app, and so no camera permission to ask for),
/// - a link to send in Messages,
/// - and the six characters, for reading out loud.
struct InviteView: View {
    let invite: SyncClient.Invite
    let babyName: String

    @Environment(\.dismiss) private var dismiss

    private var link: URL? {
        guard let server = SyncCredentials.serverURL else { return nil }
        return SyncLink.url(code: invite.code, server: server)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let image = qrImage {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(16)
                            .background(.white, in: .rect(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                            .accessibilityLabel("QR code containing the invite")
                    }

                    Text("Point the other iPhone's Camera at this. Tap the banner it shows, and Baby Feed opens ready to join.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 6) {
                        Text("Or type this code")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(invite.code)
                            .font(.system(size: 40, weight: .semibold, design: .monospaced))
                            .tracking(6)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    Text("Expires \(invite.expiresAt, format: .relative(presentation: .named)). It works once.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let link {
                        ShareLink(item: link,
                                  message: Text(SyncMerge.inviteMessage(babyName: babyName, code: invite.code))) {
                            Label("Send the invite", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Invite a caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Building one of these allocates render resources, so it is made once
    /// rather than on every pass through `body`.
    private static let ciContext = CIContext()

    /// Rendered at the QR's native size and scaled up without smoothing — a
    /// blurred QR is one a camera won't read.
    private var qrImage: UIImage? {
        guard let link, let data = link.absoluteString.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // M: survives a fingerprint on the screen, still compact enough to read
        // across a room in bad light.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = Self.ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
