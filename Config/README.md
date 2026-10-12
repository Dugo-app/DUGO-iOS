<!--
  README.md
  DuGo-iOS

  Created by 김승원 on 12/10/26.
-->

# 앱 설정

`AppURLs.xcconfig`에는 공개 가능한 도움말·개인정보 처리방침 주소만 둡니다. 앱은 이 값을 `Info.plist`를 거쳐 `AppEnvironment`에서 읽습니다.

Firebase 설정 파일은 Git에 올리지 않습니다. Firebase 콘솔에서 각 앱의 Apple 설정 파일을 내려받아 아래 위치에 넣으세요.

| 앱 | 번들 ID | 로컬 파일 |
| --- | --- | --- |
| 두고 | `app.seungwon.dugo` | `DuGo-iOS/GoogleService-Info.plist` |
| 두고dev | `app.seungwon.dugo.dev` | `DuGo-iOS/GoogleService-Info-Dev.plist` |

두 파일은 `.gitignore`에 포함되어 있으며, Xcode 빌드에는 로컬 파일이 필요합니다. 기존에 Git에 올라간 키 값은 기록에 남으므로 Google Cloud Console에서 해당 키의 API·iOS 앱 제한을 확인하고, 필요한 경우 키를 교체하세요. Firebase의 클라이언트 API 키는 앱 번들에도 포함되므로 파일을 Git에서 제외하는 것만으로 비밀 키가 되지는 않습니다.
