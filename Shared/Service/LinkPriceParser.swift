//
//  LinkPriceParser.swift
//  DuGo-iOS
//
//  Created by 김승원 on 1/10/26.
//

import CoreFoundation
import Foundation

enum LinkPriceParser {
    nonisolated static func krwAmount(_ rawAmount: String, currency: String) -> Int? {
        guard currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "KRW" else {
            return nil
        }
        let amount = rawAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            amount.range(
                of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.0+)?$"#,
                options: .regularExpression
            ) != nil
        else { return nil }
        let integer = amount.replacingOccurrences(of: ",", with: "").split(separator: ".")[0]
        return Int(integer)
    }

    nonisolated static func productPrice(in value: Any) -> Int? {
        let prices = Set(productPrices(in: value))
        return prices.count == 1 ? prices.first : nil
    }

    nonisolated private static func productPrices(in value: Any) -> [Int] {
        if let array = value as? [Any] {
            return array.flatMap(productPrices)
        }
        guard let object = value as? [String: Any] else { return [] }
        let types = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
        if types.contains(where: {
            ["Product", "https://schema.org/Product", "http://schema.org/Product"].contains($0)
        }) {
            let offers =
                (object["offers"] as? [[String: Any]]) ?? (object["offers"] as? [String: Any]).map {
                    [$0]
                } ?? []
            return offers.compactMap { offer in
                guard let currency = offer["priceCurrency"] as? String else { return nil }
                if let amount = offer["price"] as? String {
                    return krwAmount(amount, currency: currency)
                }
                if let amount = offer["price"] as? NSNumber,
                    CFGetTypeID(amount) != CFBooleanGetTypeID()
                {
                    return krwAmount(amount.stringValue, currency: currency)
                }
                return nil
            }
        }
        return object["@graph"].map(productPrices) ?? []
    }
}
