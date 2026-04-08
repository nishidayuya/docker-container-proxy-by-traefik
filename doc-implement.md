# 実装計画: Traefikによるコンテナ・ポート自動ルーティング

## 1. 目的
`http://<container-name>-<port>.localhost/` 形式のURLへのリクエストを、Docker上で動作している該当コンテナの指定ポートへ自動的に転送する環境を構築する。

## 2. アーキテクチャ
以下の2つのコンテナをベースとした構成とする。

1.  **Traefik (本体)**:
    - エントリポイントとして動作。
    - `File Provider` を有効にし、動的に生成される設定ファイルを監視する。
2.  **Configuration Generator (サイドカー / Ruby)**:
    - Dockerソケットを監視。
    - コンテナの起動・停止を検知し、現在実行中の全コンテナと公開ポートのリストから Traefik 用の動的設定ファイル (`dynamic_conf.yml`) を自動生成する。

## 3. 実装詳細

### 3.1. Traefik の設定
`docker-compose.yml` で以下を定義する。
- Dockerソケットの読み取り権限はサイドカーにのみ与える。
- `config/` ディレクトリをマウントし、`providers.file.directory` で監視する。

### 3.2. Configuration Generator (Ruby 3.1+)
`docker-api` ジェムを使用して以下の処理を行う。
1.  `Docker::Event.stream` でコンテナの `start`, `die`, `destroy` イベントを監視。
2.  イベント検知時、または起動時に実行中の全コンテナ情報を取得。
3.  各コンテナの `Name` と、公開（Expose）されているポートを抽出。
4.  以下の形式の Traefik 設定を生成し、`config/dynamic_conf.yml` に書き出す。
    - **Router**: `Host("<container>-<port>.localhost")`
    - **Service**: `url: "http://<container-ip>:<port>"`
5.  実装には Ruby 3.1+ の Hash 値省略記法（例: `{ port: }`）などを活用する。

### 3.3. ディレクトリ構成案
```text
.
├── docker-compose.yml
├── traefik/
│   └── traefik.yml (静的設定)
├── config/
│   └── dynamic_conf.yml (自動生成されるファイル)
└── generator/
    ├── Dockerfile
    ├── Gemfile
    └── generator.rb
```

## 4. 動作フロー
1.  ユーザーが `http://some-nginx-8080.localhost/` にアクセス。
2.  Traefik が `dynamic_conf.yml` 内の該当ルールを検索。
3.  コンテナ `some-nginx` の内部 IP アドレスとポート `8080` へリクエストを転送。

## 5. 次のステップ
1.  `generator/` 配下の Ruby スクリプトと Dockerfile の作成。
2.  Traefik 設定ファイルおよび `docker-compose.yml` の作成。
3.  テスト用コンテナを起動し、自動ルーティングの動作確認。
