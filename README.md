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
| `lib/models.dart` | `Flashcard`（SM-2 の状態を持つ）と `CardStore`（`shared_preferences` で端末内に JSON 保存） |
| `lib/main.dart` | アプリ本体・デッキ絞り込み・カード一覧（追加/編集/スワイプ削除） |
| `lib/study_screen.dart` | 学習モード（タップで裏返し、3段階で自己評価） |
| `lib/import_screen.dart` | タブ区切りテキストからの一括取り込み |
| `test/widget_test.dart` | 16件。SM-2 の遷移・キュー・パーサ・重複除外・永続化・3画面 |
| `.github/workflows/ios.yml` | GitHub Actions で **署名なし .ipa** を作る |

### 間隔反復（SM-2）

出題対象は「期限が来たカード」だけ。評価は3段階で、押すと次回の出題日が決まる。

- **もう一度** … `reps` を 0、間隔を 0 に戻し `ease` を 0.20 下げる（下限 1.3）。
  翌日送りにせず**そのセッションの末尾に積み直す**ので、覚えていないカードをその場で潰せる
- **できた** … 1日 → 6日 → 前回の間隔 × `ease`
- **簡単** … 上に 1.3 倍を掛け、`ease` を 0.15 上げる（上限 3.0）

ボタンには「押したら次はいつ出るか」を表示する。間隔が見えていれば「簡単」を
押しすぎたときに自分で気づける。

### 一括取り込み

Excel やスプレッドシートで2列を選んでコピーするとタブ区切りになるので、それをそのまま貼る。
1行1枚。タブが無い行は表だけのカード、3列目以降は改行で連結して裏にする。
**同じデッキに同じ表があれば飛ばす**ので、同じ範囲を二度貼っても重複しない。

### UI 実装で踏んだこと

- **`ChoiceChip` は使えない。** Flutter web で日本語ラベルの幅を大幅に過小評価し、
  「すべて 3」が「す」まで切り詰められた。同じ文字列は AppBar・ListTile・
  `FilledButton` では正しく出るので Chip 固有。`labelPadding` を足しても
  幅が広がるだけで切れ幅は変わらない。`FilledButton.tonal` / `OutlinedButton` に
  `StadiumBorder` を当てて自作している。
  **`flutter test` では検出できない**（テスト用フォントは全字が等幅なので overflow が出ない）
- 画面を積む `Column` は既定が `CrossAxisAlignment.center` で、
  横スクロール行が中央寄せかつ内容幅に縮む。`stretch` を明示している

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

`zip -y`（symlink を symlink のまま保存）は付けてあるが、**iOS では実際には効いていない**。
実際に焼いた .ipa を検証したところ symlink エントリは 0 個だった。iOS のフレームワークは
フラット構造（`App.framework/App` が直に置かれる）で、`Versions/A` への symlink を使うのは
macOS のフレームワーク形式だから。無害なので防御的に残しているが、iOS 向けでは必須ではない。

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
