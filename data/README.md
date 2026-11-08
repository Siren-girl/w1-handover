# data

原始数据与处理产物**不入库**（`.gitignore` 里 `data/*` + `*.parquet` 等规则）。
本文件靠 `!data/README.md` 取反规则保留，作用是让 `data/` 目录本身进 git。

- 数据来源与拉取方式：`scripts/pull_episodes.sh`（W1 §8.6）
- 目录约定：`data/raw/` 原始下载，`data/out/` 处理产物，两者都不提交
