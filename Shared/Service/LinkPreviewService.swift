//
//  LinkPreviewService.swift
//  DuGo-iOS
//
//  Created by 김승원 on 20/9/26.
//

import Foundation
@preconcurrency import LinkPresentation
import UIKit

struct LinkPreview {
    let title: String?
    let imageData: Data?
    let price: Int?
}

private final class LinkMetadataProviderLifetime: @unchecked Sendable {
    let provider = LPMetadataProvider()
}

enum LinkPreviewError: LocalizedError {
    case invalidLink
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            "대표 사진을 가져올 수 없는 링크예요"
        case .invalidResponse:
            "웹사이트에서 대표 사진을 찾지 못했어요"
        }
    }
}

struct LinkPreviewService {
    // MARK: - Properties

    private let adapters: [any ShoppingLinkAdapter] = [
        MusinsaLinkAdapter(),
        OliveYoungLinkAdapter(),
    ]

    // MARK: - Methods

    func fetch(from rawLink: String) async throws -> LinkPreview {
        let link = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: link),
            let scheme = pageURL.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            pageURL.host != nil
        else {
            throw LinkPreviewError.invalidLink
        }

        let adapter = adapter(for: pageURL)
        let resolvedPageURL = await adapter?.resolvedURL(from: pageURL) ?? pageURL
        let fallbackPriceTask = adapter.map { adapter in
            Task { await adapter.fallbackPrice(from: resolvedPageURL) }
        }

        do {
            let preview = try await fetchPage(from: resolvedPageURL, remainingRedirects: 2)
            if preview.price != nil {
                fallbackPriceTask?.cancel()
                return preview
            }

            guard let fallbackPriceTask else { return preview }
            let price = await fallbackPriceTask.value
            return LinkPreview(
                title: preview.title,
                imageData: preview.imageData,
                price: price
            )
        } catch {
            guard let fallbackPriceTask,
                let price = await fallbackPriceTask.value
            else {
                throw error
            }
            return LinkPreview(title: nil, imageData: nil, price: price)
        }
    }

    nonisolated static func usableProductTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(title.count) else { return nil }

        let normalized = title.lowercased()
        guard !normalized.hasPrefix("launching app"),
            !normalized.hasPrefix("opening app"),
            !normalized.hasPrefix("deeplink redirect"),
            !normalized.hasPrefix("쿠팡을 추천합니다"),
            !normalized.contains("attention required! | cloudflare")
        else { return nil }

        return title
    }

    // MARK: - Private Methods

    private func adapter(for url: URL) -> (any ShoppingLinkAdapter)? {
        adapters.first { $0.matches(url) }
    }

    private func normalizedProductURL(from url: URL) -> URL? {
        adapters.lazy.compactMap { $0.normalizedURL(from: url) }.first
    }

    private func fetchPage(from pageURL: URL, remainingRedirects: Int) async throws -> LinkPreview {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (htmlData, response) = try await URLSession.shared.data(for: request)
            let html =
                htmlData.count <= 2_000_000
                ? (String(data: htmlData, encoding: .utf8)
                    ?? String(data: htmlData, encoding: .unicode))
                : nil

            let resolvedURL = response.url ?? pageURL
            let pageTitle = html.flatMap(pageTitle(in:))
            let hasUsableTitle = html.flatMap {
                Self.usableProductTitle(metadataValue(named: "og:title", in: $0))
                    ?? Self.usableProductTitle(metadataValue(named: "twitter:title", in: $0))
            } ?? Self.usableProductTitle(pageTitle)
            if remainingRedirects > 0,
                let productURL = destinationURL(
                    from: resolvedURL,
                    html: html,
                    hasUsableTitle: hasUsableTitle != nil
                ),
                productURL != pageURL,
                productURL != resolvedURL
            {
                return try await fetchPage(from: productURL, remainingRedirects: remainingRedirects - 1)
            }

            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode),
                let html
            else {
                throw LinkPreviewError.invalidResponse
            }

            let title =
                Self.usableProductTitle(metadataValue(named: "og:title", in: html))
                ?? Self.usableProductTitle(metadataValue(named: "twitter:title", in: html))
                ?? Self.usableProductTitle(pageTitle)
            let imagePath =
                metadataValue(named: "og:image", in: html)
                ?? metadataValue(named: "twitter:image", in: html)
            let imageURL = imagePath.flatMap {
                URL(string: decodedHTML($0), relativeTo: resolvedURL)?.absoluteURL
            }
            let imageData = try? await loadImage(from: imageURL)
            try Task.checkCancellation()

            if title != nil, imageData != nil {
                return LinkPreview(
                    title: title.map(decodedHTML),
                    imageData: imageData,
                    price: productPrice(in: html, pageURL: resolvedURL)
                )
            }

            let systemPreview = await systemLinkPreview(for: resolvedURL)
            return LinkPreview(
                title: title.map(decodedHTML) ?? systemPreview?.title,
                imageData: imageData ?? systemPreview?.imageData,
                price: productPrice(in: html, pageURL: resolvedURL)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let systemPreview = await systemLinkPreview(for: pageURL) {
                return systemPreview
            }
            throw error
        }
    }

    private func destinationURL(from pageURL: URL, html: String?, hasUsableTitle: Bool) -> URL? {
        if let normalizedURL = normalizedProductURL(from: pageURL), normalizedURL != pageURL {
            return normalizedURL
        }

        guard !hasUsableTitle else { return nil }

        let queryNames = ["af_web_dp", "af_ios_url", "af_android_url", "deep_link_value", "url", "link"]
        if let components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
            for name in queryNames {
                if let value = components.queryItems?.first(where: { $0.name == name })?.value,
                    let destination = webDestination(value, relativeTo: pageURL),
                    destination != pageURL
                {
                    return destination
                }
            }
        }

        guard let html else { return nil }

        let scriptPatterns = [
            #"(?i)\b(?:store_link|web_link|redirectWebUrl|af_web_dp|fallback_url)\s*[:=]\s*['\"]([^'\"]+)['\"]"#,
            #"(?i)\b(?:window\.)?location(?:\.href)?\s*=\s*['\"]([^'\"]+)['\"]"#,
        ]
        for pattern in scriptPatterns {
            if let value = firstCapture(for: pattern, in: html),
                let destination = webDestination(value, relativeTo: pageURL),
                destination != pageURL
            {
                return destination
            }
        }

        if let value = metadataValue(named: "og:url", in: html),
            let destination = webDestination(value, relativeTo: pageURL),
            destination != pageURL
        {
            return destination
        }

        for tag in matches(for: #"(?is)<link\b[^>]*>"#, in: html) {
            if attribute(named: "rel", in: tag)?.lowercased() == "canonical",
                let value = attribute(named: "href", in: tag),
                let destination = webDestination(value, relativeTo: pageURL),
                destination != pageURL
            {
                return destination
            }
        }

        return nil
    }

    private func webDestination(_ value: String, relativeTo pageURL: URL) -> URL? {
        var decoded = decodedHTML(value)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        decoded = decodedJavaScriptEscapes(decoded)
        if decoded.hasPrefix("%"), let percentDecoded = decoded.removingPercentEncoding {
            decoded = percentDecoded
        }

        guard let url = URL(string: decoded, relativeTo: pageURL)?.absoluteURL,
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else { return nil }

        return normalizedProductURL(from: url) ?? url
    }

    private func decodedJavaScriptEscapes(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\\x([0-9a-fA-F]{2})"#) else {
            return value
        }

        var result = value
        let matches = expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
        for match in matches.reversed() {
            guard let hexRange = Range(match.range(at: 1), in: result),
                let replacementRange = Range(match.range, in: result),
                let code = UInt8(result[hexRange], radix: 16)
            else { continue }
            result.replaceSubrange(replacementRange, with: String(UnicodeScalar(code)))
        }
        return result
    }

    private func firstCapture(for pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private func productPrice(in html: String, pageURL: URL) -> Int? {
        for prefix in ["product:price:", "og:price:"] {
            if let currency = metadataValue(named: prefix + "currency", in: html),
                let amount = metadataValue(named: prefix + "amount", in: html),
                let price = LinkPriceParser.krwAmount(amount, currency: currency)
            {
                return price
            }
        }

        for script in matches(for: #"(?is)<script\b[^>]*>.*?</script\s*>"#, in: html) {
            guard let openingEnd = script.firstIndex(of: ">"),
                attribute(named: "type", in: String(script[...openingEnd]))?.lowercased()
                    == "application/ld+json",
                let closing = script.range(of: "</script", options: [.backwards, .caseInsensitive])
            else { continue }
            let json = String(script[script.index(after: openingEnd)..<closing.lowerBound])
            guard let data = json.data(using: .utf8),
                let value = try? JSONSerialization.jsonObject(with: data),
                let price = LinkPriceParser.productPrice(in: value)
            else { continue }
            return price
        }

        return adapter(for: pageURL)?.price(in: html)
    }

    private func loadImage(from url: URL?) async throws -> Data? {
        guard let url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            data.count <= 12_000_000,
            let image = UIImage(data: data)
        else {
            return nil
        }

        return resizedJPEGData(from: image)
    }

    private func systemLinkPreview(for url: URL) async -> LinkPreview? {
        let metadata: LPLinkMetadata? = await withCheckedContinuation { continuation in
            let lifetime = LinkMetadataProviderLifetime()
            lifetime.provider.timeout = 15
            lifetime.provider.startFetchingMetadata(for: url) { metadata, _ in
                withExtendedLifetime(lifetime) {
                    continuation.resume(returning: metadata)
                }
            }
        }
        guard let metadata else { return nil }

        let title = Self.usableProductTitle(metadata.title)
        if metadata.title != nil, title == nil { return nil }
        let imageData = await imageData(from: metadata.imageProvider)
        guard title != nil || imageData != nil else { return nil }

        return LinkPreview(
            title: title,
            imageData: imageData,
            price: nil
        )
    }

    private func imageData(from provider: NSItemProvider?) async -> Data? {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return nil }

        let image: UIImage? = await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        return image.flatMap(resizedJPEGData)
    }

    private func metadataValue(named name: String, in html: String) -> String? {
        let metaTags = matches(for: #"(?is)<meta\b[^>]*>"#, in: html)

        for tag in metaTags {
            let key =
                attribute(named: "property", in: tag)
                ?? attribute(named: "name", in: tag)
                ?? attribute(named: "itemprop", in: tag)

            if key?.lowercased() == name.lowercased(),
                let content = attribute(named: "content", in: tag),
                !content.isEmpty
            {
                return content
            }
        }

        return nil
    }

    private func pageTitle(in html: String) -> String? {
        guard let title = matches(for: #"(?is)<title[^>]*>\s*(.*?)\s*</title>"#, in: html).first
        else {
            return nil
        }

        return
            title
            .replacingOccurrences(of: #"(?is)</?[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attribute(named name: String, in tag: String) -> String? {
        let pattern = #"(?i)\b\#(name)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else {
            return nil
        }

        for index in 1...3 {
            let range = match.range(at: index)
            if range.location != NSNotFound,
                let swiftRange = Range(range, in: tag)
            {
                return String(tag[swiftRange])
            }
        }

        return nil
    }

    private func matches(for pattern: String, in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)

        return expression.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return String(value[swiftRange])
        }
    }

    private func decodedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    func resizedJPEGData(from image: UIImage) -> Data? {
        let maximumDimension: CGFloat = 1_200
        let sourceSize = image.size
        let ratio = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let resizedImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.82)
    }
}
