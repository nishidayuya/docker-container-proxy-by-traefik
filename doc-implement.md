# 実装計画: Traefikによるコンテナ・ポート自動ルーティング

## 1. 目的
`http://<container-name>-<port>.localhost/` 形式のURLへのリクエストを、Docker上で動作している該当コンテナの指定ポートへ自動的に転送する環境を構築する。

## 2. アーキテクチャ
以下の2つのコンテナをベースとした構成とする。

1.  **Traefik (本体)**:
    - エントリポイントとして動作。
    - `File Provider` を有効にし、動的に生成される設定ファイルを監視する。
2.  **Configuration Generator (サイドカー)**:
    - Dockerソケットを監視。
    - コンテナの起動・停止を検知し、現在実行中の全コンテナと公開ポートのリストから Traefik 用の動的設定ファイル (`dynamic_conf.yml`) を自動生成する。

## 3. 実装詳細

### 3.1. Traefik の設定
`docker-compose.yml` で以下を定義する。
- Dockerソケットの外部公開は不要（サイドカーが行うため）。
- `dynamic_conf.yml` が配置されるディレクトリをマウントし、`providers.file.directory` で監視する。

### 3.2. Configuration Generator (Python)
`docker-py` を使用して以下の処理を行う。
1.  Docker API で実行中の全コンテナを取得。
2.  各コンテナの `Name` と、公開されているすべての `ExposedPorts` または `Ports` を抽出。
3.  以下の形式の Traefik 設定を生成。
    - **Router**: `Host("<container>-<port>.localhost")`
    - **Service**: `url: "http://<container-ip>:<port>"`
4.  設定を YAML ファイルとして書き出す。

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
    ├── main.py
    └── requirements.txt
```

## 4. 動作フロー
1.  ユーザーが `http://my-nginx-8080.localhost/` にアクセス。
2.  Traefik が `dynamic_conf.yml` 内の該当ルールを検索。
3.  コンテナ `my-nginx` の IP アドレスとポート `8080` へリクエストを転送。

## 5. 次のステップ
1.  `docker-compose.yml` の作成。
2.  Configuration Generator の実装。
3.  動作確認用のサンプルコンテナによるテスト。
