import SwiftUI

// MARK: - FlagBadge

/// A behavior-flag chip. Danger flags (bite / anxious / senior) render red;
/// always carries text + icon so it is legible without color (spec section 20).
struct FlagBadge: View {
    let flag: BehaviorFlag

    var body: some View {
        Label {
            Text(flag.rawValue)
        } icon: {
            Image(systemName: flag.symbolName)
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }

    private var tint: Color {
        flag.isDanger ? .red : .secondary
    }
}

// MARK: - RabiesExpiryBadge

/// Highlights an expired rabies vaccination. Renders nothing for a non-expired
/// or missing date so callers can drop it in unconditionally.
struct RabiesExpiryBadge: View {
    let expiry: Date?

    private var isExpired: Bool {
        guard let expiry else { return false }
        return expiry < Date()
    }

    var body: some View {
        if isExpired {
            Label("Rabies expired", systemImage: "syringe")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)
        }
    }
}

// MARK: - PhotoThumb
//
// NOTE: `PhotoThumb(fileName:size:)` is defined by the Pets slice
// (`PetsListView.swift`) and reused across the app, so this slice does not
// redefine it to avoid a duplicate-type compile error.

// MARK: - EmptyStateView

/// Centered placeholder for empty lists.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - SectionCard

/// A titled card container used to group content outside of `Form`/`List`.
struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            } else {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
