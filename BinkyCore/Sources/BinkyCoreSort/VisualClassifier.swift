import AppKit
import CoreServices
import Foundation
import ImageIO
import PDFKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a picture (or a PDF's first page) shows. A file can carry more than one:
/// a phone photo of a receipt is both `.photo` and `.receipt`.
enum SortVisualCategory: String, Sendable, Hashable {
    case screenshot
    case photo
    case documentScan
    case receipt
    case ticket
}

/// Looks at images. File metadata answers screenshot / photo on every release;
/// on macOS 27+ the on-device model looks at the picture itself.
enum VisualClassifier {

    static func traits(for url: URL, isPDF: Bool) async -> Set<SortVisualCategory> {
        var traits: Set<SortVisualCategory> = []
        if !isPDF {
            traits.formUnion(metadataTraits(for: url))
        }

        #if canImport(FoundationModels)
        if #available(macOS 27.0, *), let image = thumbnail(for: url, isPDF: isPDF, maxPixelSize: 768) {
            if let seen = await modelTrait(for: image) {
                traits.insert(seen)
            }
        }
        #endif

        return traits
    }

    // MARK: - Metadata (all releases)

    private static func metadataTraits(for url: URL) -> Set<SortVisualCategory> {
        var traits: Set<SortVisualCategory> = []

        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let isCapture = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool,
           isCapture {
            traits.insert(.screenshot)
        } else if FileClassification.categorize(url: url) == .screenshots {
            traits.insert(.screenshot)
        }

        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let hasExposure = exif?[kCGImagePropertyExifExposureTime] != nil
            if !make.isEmpty || hasExposure {
                traits.insert(.photo)
            }
        }

        return traits
    }

    private static func thumbnail(for url: URL, isPDF: Bool, maxPixelSize: Int) -> CGImage? {
        if isPDF {
            guard let doc = PDFDocument(url: url), doc.pageCount > 0, let page = doc.page(at: 0) else { return nil }
            let thumb = page.thumbnail(of: CGSize(width: maxPixelSize, height: maxPixelSize), for: .mediaBox)
            var rect = CGRect(origin: .zero, size: thumb.size)
            return thumb.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    // MARK: - On-device vision (macOS 27+)

    #if canImport(FoundationModels)
    @available(macOS 27.0, *)
    @Generable(description: "The single best description of what the image shows.")
    fileprivate enum SeenKind {
        case screenshot
        case cameraPhoto
        case scannedDocument
        case receiptOrInvoice
        case ticketOrPass
        case other
    }

    @available(macOS 27.0, *)
    private static func modelTrait(for image: CGImage) async -> SortVisualCategory? {
        let model = SystemLanguageModel.default
        guard model.availability == .available, model.capabilities.contains(.vision) else { return nil }

        let instructions = """
        You sort files in a Downloads folder. Classify the image.
        screenshot: a capture of a computer or phone screen (app windows, web pages, chats).
        cameraPhoto: taken with a camera (people, places, things), not mainly a document.
        scannedDocument: a page of paper photographed or scanned (letters, forms, contracts).
        receiptOrInvoice: a purchase receipt, invoice, or bill with amounts.
        ticketOrPass: a boarding pass, event or train ticket, or a QR/barcode pass.
        other: none of these.
        """
        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(generating: SeenKind.self) {
                "What does this image show?"
                Attachment(image)
            }
            switch response.content {
            case .screenshot: return .screenshot
            case .cameraPhoto: return .photo
            case .scannedDocument: return .documentScan
            case .receiptOrInvoice: return .receipt
            case .ticketOrPass: return .ticket
            case .other: return nil
            }
        } catch {
            return nil
        }
    }
    #endif
}
