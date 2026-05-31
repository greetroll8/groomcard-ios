import UIKit
import PDFKit

/// Generates client-facing PDF documents (grooming report + signed consent) using
/// `UIGraphicsPDFRenderer`. All text is drawn with the system font (a Unicode font)
/// so Cyrillic and diacritics in `consent.resolvedText` / pet data render correctly.
///
/// Both entry points return a temp-file `URL` ready to hand to `ShareSheet`.
enum PDFExport {

    // MARK: - Page geometry (US Letter, 72 dpi)

    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 48
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    // MARK: - Fonts / colors

    private static let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
    private static let headingFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    private static let smallFont = UIFont.systemFont(ofSize: 9, weight: .regular)
    private static let primaryColor = UIColor(red: 0.10, green: 0.45, blue: 0.55, alpha: 1) // teal/blue-green
    private static let dangerColor = UIColor.systemRed
    private static let mutedColor = UIColor.darkGray

    // MARK: - Grooming report

    /// Header (business + report number), pet identity & flags, before/after photo
    /// rows, style, recommendations, price and date.
    @MainActor
    static func groomingReportPDF(store: GroomStore, session: GroomSession) -> URL {
        let pet = store.pet(id: session.petId)
        let reportNumber = store.nextReportNumber()
        let business = store.settings.businessInfo

        // Resolve all store-dependent data on the main actor BEFORE entering the
        // nonisolated PDF render closure, then capture only plain values
        // (UIImages, value structs) into it. The render closure runs synchronously
        // in a nonisolated context, so it must not touch the @MainActor store.
        let beforeImages = Self.loadImages(store: store, ids: session.beforePhotoIds)
        let afterImages = Self.loadImages(store: store, ids: session.afterPhotoIds)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let url = tempURL(prefix: "GroomingReport")

        try? renderer.writePDF(to: url) { ctx in
            var pen = Pen(ctx: ctx)
            pen.beginPage()

            drawBusinessHeader(business, pen: &pen)
            pen.drawRightAligned(reportNumber, font: smallFont, color: mutedColor, topOfBlock: margin)

            pen.title("Grooming Report")
            pen.gap(6)
            pen.body(session.date.formatted(date: .abbreviated, time: .omitted), color: mutedColor)
            pen.rule()

            // Pet identity.
            pen.heading("Pet")
            if let pet {
                pen.body(petIdentityLine(pet))
                if !pet.breed.isEmpty { pen.body("Breed: \(pet.breed)") }
                pen.body("Coat: \(pet.coatType.rawValue)")
                if !pet.allergies.isEmpty { pen.body("Allergies: \(pet.allergies)") }
                drawFlags(pet.displayFlags, pen: &pen)
            } else {
                pen.body("\u{2014}", color: mutedColor)
            }
            pen.gap(8)

            // Before / after photos (resolved above on the main actor).
            if !beforeImages.isEmpty || !afterImages.isEmpty {
                pen.heading("Before / After")
                drawPhotoRow(before: beforeImages.first, after: afterImages.first, pen: &pen)
                pen.gap(8)
            }

            // Style.
            if !session.style.isEmpty {
                pen.heading("Style")
                pen.body(session.style)
                pen.gap(6)
            }

            // Recommendations.
            if !session.recommendations.isEmpty {
                pen.heading("Recommendations")
                pen.body(session.recommendations)
                pen.gap(6)
            }

            // Notes.
            if !session.notes.isEmpty {
                pen.heading("Notes")
                pen.body(session.notes)
                pen.gap(6)
            }

            // Price.
            if let price = session.price {
                pen.rule()
                let amount = NSDecimalNumber(decimal: price).doubleValue
                let formatted = amount.formatted(.currency(code: session.currencyCode))
                pen.heading("Price: \(formatted)")
            }

            drawFooter(pen: &pen)
        }

        return url
    }

    // MARK: - Consent

    /// Business header + consent number, full `resolvedText`, mat-removal choice,
    /// photo-release line, embedded signature image and the signing metadata.
    @MainActor
    static func consentPDF(store: GroomStore, pet: Pet, consent: Consent) -> URL {
        let consentNumber = store.nextConsentNumber()
        let business = store.settings.businessInfo

        // Resolve the signature image on the main actor before the render closure
        // (which is nonisolated) so the closure never touches the @MainActor store.
        let signatureImage = ImageStore.load(fileName: store.photo(id: consent.signaturePhotoId)?.fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let url = tempURL(prefix: "Consent")

        try? renderer.writePDF(to: url) { ctx in
            var pen = Pen(ctx: ctx)
            pen.beginPage()

            drawBusinessHeader(business, pen: &pen)
            pen.drawRightAligned(consentNumber, font: smallFont, color: mutedColor, topOfBlock: margin)

            pen.title("Grooming Consent")
            pen.gap(6)
            pen.rule()

            // Pet line.
            pen.heading("Pet")
            pen.body(petIdentityLine(pet))
            if !pet.breed.isEmpty { pen.body("Breed: \(pet.breed)") }
            pen.gap(8)

            // Consent body text (Cyrillic-safe via system font).
            pen.heading("Consent")
            let text = consent.resolvedText.isEmpty
                ? AppSettings.defaultConsentTemplate
                : consent.resolvedText
            pen.body(text)
            pen.gap(8)

            // Structured choices.
            pen.heading("Selections")
            pen.body("Mat removal: \(consent.matRemovalChoice.rawValue)")
            pen.body("Photo release: \(consent.photoReleaseAllowed ? "Allowed" : "Not allowed")")
            pen.body("Sedation-free acknowledged: \(consent.sedationFreeAcknowledged ? "Yes" : "No")")
            if consent.seniorRiskAcknowledged {
                pen.body("Senior risk acknowledged: Yes")
            }
            pen.gap(10)

            // Signature (resolved above on the main actor).
            pen.heading("Signature")
            if let sig = signatureImage {
                drawSignature(sig, pen: &pen)
            } else {
                pen.body("(unsigned)", color: dangerColor)
            }
            pen.gap(4)
            pen.body("Signed: \(consent.signedAt.formatted(date: .abbreviated, time: .shortened))", color: mutedColor)
            pen.body("Consent text version: \(consent.textVersion)", color: mutedColor)

            drawFooter(pen: &pen)
        }

        return url
    }

    // MARK: - Shared drawing helpers

    private static func drawBusinessHeader(_ business: BusinessInfo, pen: inout Pen) {
        let name = business.name.isEmpty ? "GroomCard" : business.name
        pen.text(name, font: headingFont, color: primaryColor)
        var contact: [String] = []
        if !business.phone.isEmpty { contact.append(business.phone) }
        if !business.email.isEmpty { contact.append(business.email) }
        if !contact.isEmpty { pen.text(contact.joined(separator: "  \u{00B7}  "), font: smallFont, color: mutedColor) }
        if !business.address.isEmpty { pen.text(business.address, font: smallFont, color: mutedColor) }
        if !business.licenseNumber.isEmpty {
            pen.text("License: \(business.licenseNumber)", font: smallFont, color: mutedColor)
        }
        pen.gap(10)
    }

    private static func drawFlags(_ flags: [BehaviorFlag], pen: inout Pen) {
        guard !flags.isEmpty else { return }
        for flag in flags {
            let color = flag.isDanger ? dangerColor : mutedColor
            let prefix = flag.isDanger ? "\u{26A0} " : "\u{2022} "
            pen.body(prefix + flag.rawValue, color: color)
        }
    }

    private static func petIdentityLine(_ pet: Pet) -> String {
        "\(pet.name) (\(pet.species.rawValue))"
    }

    /// Resolves PhotoAsset ids to loaded UIImages. Marked @MainActor because it
    /// reads the main-actor store; callers invoke it on the main actor before
    /// handing the plain UIImages to the nonisolated render closure.
    @MainActor
    private static func loadImages(store: GroomStore, ids: [UUID]) -> [UIImage] {
        ids.compactMap { ImageStore.load(fileName: store.photo(id: $0)?.fileName) }
    }

    private static func drawPhotoRow(before: UIImage?, after: UIImage?, pen: inout Pen) {
        let cellWidth = (contentWidth - 16) / 2
        let cellHeight: CGFloat = 150
        pen.ensureSpace(cellHeight + 24)

        let topY = pen.cursorY
        drawLabeledImage("Before", image: before, x: margin, y: topY, width: cellWidth, height: cellHeight, pen: &pen)
        drawLabeledImage("After", image: after, x: margin + cellWidth + 16, y: topY, width: cellWidth, height: cellHeight, pen: &pen)
        pen.advance(cellHeight + 22)
    }

    private static func drawLabeledImage(_ label: String, image: UIImage?, x: CGFloat, y: CGFloat,
                                         width: CGFloat, height: CGFloat, pen: inout Pen) {
        let labelRect = CGRect(x: x, y: y, width: width, height: 14)
        (label as NSString).draw(in: labelRect, withAttributes: [.font: smallFont, .foregroundColor: mutedColor])
        let imageRect = CGRect(x: x, y: y + 16, width: width, height: height - 16)
        if let image {
            let fitted = aspectFit(image.size, in: imageRect.size)
            let drawRect = CGRect(
                x: imageRect.midX - fitted.width / 2,
                y: imageRect.midY - fitted.height / 2,
                width: fitted.width,
                height: fitted.height
            )
            image.draw(in: drawRect)
        } else {
            UIColor.systemGray5.setFill()
            UIBezierPath(rect: imageRect).fill()
            let placeholder = "no photo"
            let attrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: UIColor.systemGray]
            let size = (placeholder as NSString).size(withAttributes: attrs)
            (placeholder as NSString).draw(
                at: CGPoint(x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }

    private static func drawSignature(_ image: UIImage, pen: inout Pen) {
        let maxWidth = min(contentWidth, 280)
        let maxHeight: CGFloat = 110
        let fitted = aspectFit(image.size, in: CGSize(width: maxWidth, height: maxHeight))
        pen.ensureSpace(fitted.height + 6)
        let rect = CGRect(x: margin, y: pen.cursorY, width: fitted.width, height: fitted.height)
        image.draw(in: rect)
        pen.advance(fitted.height + 6)
    }

    private static func drawFooter(pen: inout Pen) {
        let footer = "Generated by GroomCard \u{00B7} \(Date().formatted(date: .abbreviated, time: .omitted))"
        let attrs: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: UIColor.systemGray2]
        let rect = CGRect(x: margin, y: pageSize.height - margin + 12, width: contentWidth, height: 14)
        (footer as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func aspectFit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func tempURL(prefix: String) -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "\(prefix)-\(stamp).pdf"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    // MARK: - Pen: a simple top-down text/graphics cursor with auto pagination

    private struct Pen {
        let ctx: UIGraphicsPDFRendererContext
        var cursorY: CGFloat = PDFExport.margin

        mutating func beginPage() {
            ctx.beginPage()
            cursorY = PDFExport.margin
        }

        mutating func newPage() {
            ctx.beginPage()
            cursorY = PDFExport.margin
        }

        /// Make sure `height` points fit below the cursor; otherwise start a new page.
        mutating func ensureSpace(_ height: CGFloat) {
            if cursorY + height > PDFExport.pageSize.height - PDFExport.margin {
                newPage()
            }
        }

        mutating func advance(_ dy: CGFloat) { cursorY += dy }
        mutating func gap(_ dy: CGFloat) { cursorY += dy }

        /// Draw a left-aligned wrapping block of text at the cursor and advance.
        mutating func text(_ string: String, font: UIFont, color: UIColor) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let maxRect = CGSize(width: PDFExport.contentWidth, height: .greatestFiniteMagnitude)
            let bounding = (string as NSString).boundingRect(
                with: maxRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
            ensureSpace(bounding.height + 2)
            let rect = CGRect(x: PDFExport.margin, y: cursorY, width: PDFExport.contentWidth, height: bounding.height)
            (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            cursorY += bounding.height + 2
        }

        mutating func title(_ s: String) { text(s, font: PDFExport.titleFont, color: PDFExport.primaryColor) }
        mutating func heading(_ s: String) { gap(4); text(s, font: PDFExport.headingFont, color: .black) }
        mutating func body(_ s: String, color: UIColor = .black) { text(s, font: PDFExport.bodyFont, color: color) }

        mutating func rule() {
            ensureSpace(10)
            cursorY += 4
            let path = UIBezierPath()
            path.move(to: CGPoint(x: PDFExport.margin, y: cursorY))
            path.addLine(to: CGPoint(x: PDFExport.pageSize.width - PDFExport.margin, y: cursorY))
            UIColor.systemGray4.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            cursorY += 8
        }

        /// Draw a string flush to the right margin, aligned with a given block top.
        mutating func drawRightAligned(_ string: String, font: UIFont, color: UIColor, topOfBlock: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (string as NSString).size(withAttributes: attrs)
            let x = PDFExport.pageSize.width - PDFExport.margin - size.width
            (string as NSString).draw(at: CGPoint(x: x, y: topOfBlock), withAttributes: attrs)
        }
    }
}
