//
//  MusinsaLinkAdapter.swift
//  DuGo-iOS
//
//  Created by 김승원 on 8/10/26.
//

import Foundation

struct MusinsaLinkAdapter: ShoppingLinkAdapter {
    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "musinsa.com" || host.hasSuffix(".musinsa.com")
    }

    func normalizedURL(from url: URL) -> URL? {
        guard matches(url) else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        let productID: String?
        if components.count >= 2, components[0] == "products" {
            productID = components[1]
        } else if components.count >= 3,
            components[0] == "app",
            components[1] == "goods"
        {
            productID = components[2]
        } else {
            productID = nil
        }

        guard let productID, !productID.isEmpty,
            productID.allSatisfy(\.isNumber)
        else {
            return nil
        }

        return URL(string: "https://www.musinsa.com/products/\(productID)")
    }
}

