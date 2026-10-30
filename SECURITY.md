# セキュリティ

## 報告のしかた

脆弱性は公開の issue に書かず、[GitHub の非公開の報告](https://github.com/kmjak/tixforge/security/advisories/new) から送ってください。内容は作者と報告者だけが見られます。

対象の例：

- guard（`scripts/guard.sh`）の確認を経ずに push・PR の作成・マージができる
- 配布している workflow（`templates/github/`）で、issue や PR の本文からコマンドを実行できる
- スクリプトが、渡された値をシェルのコードとして実行してしまう

再現手順と、使った tixforge のバージョンを添えてください。確認できたら修正版を出し、そのあとで公開します。

## 対象のバージョン

最新の版だけを直します。
