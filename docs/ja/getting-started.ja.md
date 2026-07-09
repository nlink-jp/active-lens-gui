# ActiveLens をはじめる

## 1. インストール

`ActiveLens-<version>-macos-arm64.zip` を展開し、`ActiveLens.app` を
`/Applications` に移動します。起動するとメニューバーに表示されます（Dock アイコンは
ありません）。Developer ID 署名 + notarize 済みなので、Gatekeeper の警告なしに開けます。

## 2. 記録を開始する

メニューバーの項目をクリックしてポップオーバーを開き、**Record in background** を
ON にします。これで、同梱の `active-lens daemon` をログイン時に実行する launchd
LaunchAgent が登録され、15 秒ごとにアクティビティをサンプリングします。

最初のサンプルが記録されると、トグル下のドットが緑（Recording）になります。

> `ActiveLens.app` はインストールした場所から動かさないでください。バックグラウンド
> 記録はアプリ内の CLI コピーを実行します。

## 3. 1日を振り返る

- **メニューバー**: 現在の状態と今日の *実働* 時間を表示。
- **ポップオーバー**: 今日のワークセッション（実働時間・始業時刻・操作中/閲覧の内訳・
  休憩）を表示。
- **Analysis…**: カレンダー風の稼働タイムライン（1列＝1日、各列で時刻が上→下）と日別の
  勤務ログを、直近 7 / 30 / 90 日で表示するウィンドウを開きます。

## 状態の意味

| 状態 | 意味 |
|------|------|
| operating | 入力していた（約30秒以内に入力あり） |
| present | 画面ONだが直近の入力なし（視聴・閲覧） |
| away | 画面OFF・ロック・スリープ |

## プライバシー

ActiveLens は「何を操作したか」を一切記録しません。記録するのは「入力があった事実」と
その結果の状態だけです。キーストローク・座標・ウィンドウ名・アプリ名は扱わず、特別な
権限もネットワークアクセスも不要です。

## 設定

詳細設定（サンプリング間隔・アクティブ閾値・DB保存先）は CLI の `config.toml`
（`~/Library/Application Support/active-lens/config.toml`）にあります。同梱バイナリで
`active-lens doctor` を実行すると解決値を確認できます。
[active-lens README](../../../active-lens/README.ja.md) も参照してください。
