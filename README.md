# FlashCard（暗記カード）

Windows だけで作って iPhone に入れる Flutter アプリ。Mac は使わない。

- 実体: `C:\Users\eva71\FlutterProjects\FlashCard`
- `C:\Users\eva71\Documents\クロード\FlashCard` はここへのジャンクション（別名）

## なぜ実体が「クロード」配下ではないのか

**Flutter のパスに非ASCII文字があると `flutter analyze` と VS Code の Dart 拡張が落ちる。**

`Documents\クロード\` に置いて実測した結果:

```
Unhandled exception:
FormatException: Unexpected end of input (at character 379)
...%83%BC%E3%83%89/FlashCard/"}],"capabilities":{"window":{"workDoneProgress":
```

原因は、解析サーバー（LSP）に渡すプロジェクト URI が percent-encode されて伸びるのに
`Content-Length` ヘッダがその長さを反映せず、JSON が途中で切れること。

- `dart analyze` / `flutter test` / `flutter build` は日本語パスでも通る
- 落ちるのは **LSP を使う経路だけ**（＝`flutter analyze` と IDE のエラー表示・補完）
- **ジャンクションでは回避できない**（Flutter が実パスに正規化するので、
  ASCII の別名からアクセスしても日本語の実パスが LSP に渡る）

よって実体を ASCII パスに置き、逆向きのジャンクションで `クロード\` からも辿れるようにしている。

## 開発

```bash
cd C:\Users\eva71\FlutterProjects\FlashCard
flutter run -d chrome     # Windows 上で即プレビュー（ホットリロードあり）
flutter test              # ユニット/ウィジェットテスト
flutter analyze           # 静的解析
```

Visual Studio（C++ ビルドツール）も Android Studio も入れていないので、
ローカルで動かせるターゲットは **Chrome（web）のみ**。UI の作り込みはこれで足りる。
iOS 実機での確認は CI 経由になる。

## 構成

| ファイル | 内容 |
|---|---|
| `lib/models.dart` | `Flashcard` モデルと `CardStore`（`shared_preferences` で端末内に JSON 保存） |
| `lib/main.dart` | アプリ本体・カード一覧画面（追加/編集/スワイプ削除） |
| `lib/study_screen.dart` | 学習モード（タップで裏返し、わかった/まだ で仕分け） |
| `test/widget_test.dart` | 起動・追加・出題順のテスト |
| `.github/workflows/ios.yml` | GitHub Actions で **署名なし .ipa** を作る |

出題順は「未回答 → 正答率が低い順」。苦手なカードが先に回る。

## iOS ビルド（Mac なし）

`.github/workflows/ios.yml` が GitHub Actions の macOS ランナーでビルドする。

**要点: CI では一切署名しない。** AltStore が iPhone に入れる時点で
ユーザー自身の Apple ID で再署名するため、CI に証明書も
Apple Developer Program（年99ドル）も要らない。

```yaml
flutter build ios --release --no-codesign
cd build/ios/iphoneos && mkdir -p Payload && mv Runner.app Payload/
zip -qry FlashCard.ipa Payload
```

`.ipa` は「`Payload/` に `.app` を入れて zip したもの」でしかない。
`zip -y` は symlink を symlink のまま保存する指定で、これが無いと
フレームワークの参照が壊れる。

パブリックリポジトリなので macOS ランナーは**回数無制限で無料**
（プライベートだと課金係数10倍で、無料枠2000分は macOS 換算 月200分＝15〜20ビルド）。

Flutter のバージョンは CI 側で `3.47.2` に固定してある。
ローカルの `flutter --version` を上げたら `ios.yml` の `flutter-version` も合わせること。

## iPhone に入れる

1. Actions の実行結果から `FlashCard-ipa` アーティファクト（zip）を落とす
2. 中の `FlashCard.ipa` を取り出す
3. AltServer（Windows）→ AltStore（iPhone）→ 「+」から `.ipa` を選ぶ

### 無料 Apple ID の制約

- **署名は7日で失効。** 同一 Wi-Fi 上の AltServer が再署名する
- **同時に3アプリまで**（AltStore 自体が1枠を使うので実質2）
- App ID は週10個まで（バンドルIDを変えて作り直すと消費する）

`ios/Runner/Info.plist` の `CFBundleDisplayName` がホーム画面の表示名（`暗記カード`）。
バンドルIDは `com.eva71.flashcard`（`ios/Runner.xcodeproj/project.pbxproj`）。
