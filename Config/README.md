<!--
  README.md
  DuGo-iOS

  Created by 김승원 on 12/10/26.
-->

# 앱 설정

앱 설정은 로컬 [AppConfig.plist](AppConfig.plist) 한 파일에서 관리합니다. `shareHelpURL`과 `privacyPolicyURL`에는 앱 내 웹뷰 주소를, `firebase.development`와 `firebase.release`에는 각 Firebase 앱의 값을 넣습니다. 앱은 빌드 설정에 따라 해당 환경을 선택합니다.

Firebase 콘솔에서 내려받은 Apple 설정 파일의 값을 다음과 같이 옮길 수 있습니다.

| AppConfig.plist 경로 | Firebase 설정 키 | 번들 ID |
| --- | --- | --- |
| `firebase.release` | `API_KEY`, `GCM_SENDER_ID`, `GOOGLE_APP_ID`, `PROJECT_ID`, `BUNDLE_ID`, `STORAGE_BUCKET` | `app.seungwon.dugo` |
| `firebase.development` | 같은 키 | `app.seungwon.dugo.dev` |

`AppConfig.plist`는 Git 추적에서 제외되지만 Xcode 빌드에는 필요합니다. 이미 Git에 올라간 키는 과거 기록에 남습니다. Firebase의 클라이언트 API 키도 앱 번들에 포함되므로 Git에서 제외하는 것만으로 비밀 키가 되지는 않습니다.
