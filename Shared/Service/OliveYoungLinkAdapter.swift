//
//  OliveYoungLinkAdapter.swift
//  DuGo-iOS
//
//  Created by 김승원 on 8/10/26.
//

import Foundation
import WebKit

struct OliveYoungLinkAdapter: ShoppingLinkAdapter {
    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "oy.run"
            || host == "oliveyoung.co.kr"
            || host.hasSuffix(".oliveyoung.co.kr")
    }

    func normalizedURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
            host == "oliveyoung.co.kr" || host.hasSuffix(".oliveyoung.co.kr"),
            let goodsNumber = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?.queryItems?.first(where: { $0.name == "goodsNo" })?.value,
            goodsNumber.range(
                of: #"^[A-Za-z0-9]+$"#,
                options: .regularExpression
            ) != nil
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.oliveyoung.co.kr"
        components.path = "/store/goods/getGoodsDetail.do"
        components.queryItems = [URLQueryItem(name: "goodsNo", value: goodsNumber)]
        return components.url
    }

    func resolvedURL(from url: URL) async -> URL {
        if let normalizedURL = normalizedURL(from: url) {
            return normalizedURL
        }

        guard url.host?.lowercased() == "oy.run" else { return url }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            data.count <= 512_000,
            let html = String(data: data, encoding: .utf8),
            let target = firstCapture(
                for: #""targetUrl"\s*:\s*"([^"]+)""#,
                in: html
            ),
            let targetURL = destinationURL(from: target, relativeTo: url)
        else {
            return url
        }

        return normalizedURL(from: targetURL) ?? targetURL
    }

    func price(in html: String) -> Int? {
        for property in ["eg:salePrice", "eg:originalPrice"] {
            if let amount = metadataValue(named: property, in: html),
                let price = LinkPriceParser.krwAmount(amount, currency: "KRW")
            {
                return price
            }
        }

        return nil
    }

    func fallbackPrice(from url: URL) async -> Int? {
        await OliveYoungPriceLoader().price(from: url)
    }

    private func destinationURL(from value: String, relativeTo baseURL: URL) -> URL? {
        let decoded = value
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            return nil
        }

        return url
    }

    private func metadataValue(named name: String, in html: String) -> String? {
        for tag in matches(for: #"(?is)<meta\b[^>]*>"#, in: html) {
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

    private func attribute(named name: String, in tag: String) -> String? {
        let pattern = #"(?i)\b\#(name)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: tag,
                range: NSRange(tag.startIndex..., in: tag)
            )
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

    private func firstCapture(for pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            let range = Range(match.range(at: 1), in: value)
        else {
            return nil
        }

        return String(value[range])
    }

    private func matches(for pattern: String, in value: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)

        return expression.matches(in: value, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: value) else { return nil }
            return String(value[swiftRange])
        }
    }
}

@MainActor
private final class OliveYoungPriceLoader: NSObject, WKNavigationDelegate {
    // MARK: - Properties

    private var continuation: CheckedContinuation<Int?, Never>?
    private var pollingTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }()

    // MARK: - Methods

    func price(from url: URL) async -> Int? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                webView.load(URLRequest(url: url, timeoutInterval: 12))
                startPolling()

                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled else { return }
                    self?.finish(with: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPolling()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        startPolling()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        startPolling()
    }

    // MARK: - Private Methods

    private func startPolling() {
        guard continuation != nil else { return }
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            for _ in 0..<40 {
                guard !Task.isCancelled, let self else { return }
                if let price = await currentPrice() {
                    finish(with: price)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func currentPrice() async -> Int? {
        let script = """
            (() => {
                const salePrice = document
                    .querySelector('meta[property="eg:salePrice"]')
                    ?.getAttribute('content');
                const originalPrice = document
                    .querySelector('meta[property="eg:originalPrice"]')
                    ?.getAttribute('content');
                return salePrice || originalPrice || null;
            })()
            """
        guard let value = try? await webView.evaluateJavaScript(script),
            let amount = value as? String
        else {
            return nil
        }

        return LinkPriceParser.krwAmount(amount, currency: "KRW")
    }

    private func finish(with price: Int?) {
        guard let continuation else { return }
        self.continuation = nil
        pollingTask?.cancel()
        timeoutTask?.cancel()
        webView.stopLoading()
        continuation.resume(returning: price)
    }
}

