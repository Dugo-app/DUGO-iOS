//
//  ShoppingLinkAdapter.swift
//  DuGo-iOS
//
//  Created by 김승원 on 8/10/26.
//

import Foundation

/// 공통 링크 미리보기 추출만으로 부족한 정보를 쇼핑몰별 방식으로 보완합니다.
///
/// `LinkPreviewService`는 원본 URL과 일치하는 Adapter를 찾은 뒤 URL을 해석하고,
/// 공통 메타데이터 추출 결과에 가격 정보가 없을 때 Adapter의 가격 추출을 사용합니다.
protocol ShoppingLinkAdapter {
    /// Adapter가 처리할 수 있는 쇼핑몰 URL인지 확인합니다.
    ///
    /// - Parameter url: 공유 또는 입력된 원본 URL입니다.
    /// - Returns: 해당 쇼핑몰의 URL이면 `true`입니다.
    func matches(_ url: URL) -> Bool

    /// 같은 상품을 가리키는 URL을 대표 상품 URL로 정규화합니다.
    ///
    /// - Parameter url: 정규화할 URL입니다.
    /// - Returns: 정규화할 수 있는 상품 URL이며, 대상이 아니거나 변환할 수 없으면 `nil`입니다.
    func normalizedURL(from url: URL) -> URL?

    /// 단축 링크나 리디렉션 링크를 실제 상품 URL로 해석합니다.
    ///
    /// - Parameter url: 해석할 원본 URL입니다.
    /// - Returns: 해석된 상품 URL이며, 해석할 수 없으면 원본 URL입니다.
    func resolvedURL(from url: URL) async -> URL

    /// 상품 페이지 HTML에서 쇼핑몰 전용 가격 정보를 추출합니다.
    ///
    /// - Parameter html: 상품 페이지의 HTML 문자열입니다.
    /// - Returns: 원 단위 가격이며, 추출할 수 없으면 `nil`입니다.
    func price(in html: String) -> Int?

    /// 일반 네트워크 요청으로 가격을 찾지 못했을 때 대체 방식으로 가격을 조회합니다.
    ///
    /// - Parameter url: 조회할 상품 URL입니다.
    /// - Returns: 원 단위 가격이며, 조회할 수 없으면 `nil`입니다.
    func fallbackPrice(from url: URL) async -> Int?
}

extension ShoppingLinkAdapter {
    func normalizedURL(from url: URL) -> URL? {
        nil
    }

    func resolvedURL(from url: URL) async -> URL {
        normalizedURL(from: url) ?? url
    }

    func price(in html: String) -> Int? {
        nil
    }

    func fallbackPrice(from url: URL) async -> Int? {
        nil
    }
}
