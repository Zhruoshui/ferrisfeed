# Release 自动化说明

`.github/workflows/release.yml` 在推送 `v*` tag（或在 Actions 页手动 dispatch 填版本号）时，并行构建三端产物并发布到 GitHub Release。

## 触发方式

```bash
# 方式一：打 tag 推送
git tag v1.0.0
git push origin v1.0.0

# 方式二：GitHub → Actions → Release → Run workflow，填入 v1.0.0
```

## 产物

| 端 | 产物 | 去向 |
|----|------|------|
| Android | `ferrisfeed-v1.0.0.apk`、`ferrisfeed-v1.0.0.aab`（已签名） | Release 附件 |
| Linux | `ferrisfeed-v1.0.0-linux-x64.tar.gz`、`FerrisFeed-v1.0.0-x86_64.AppImage` | Release 附件 |
| Web | Docker 镜像 `ghcr.io/zhruoshui/ferrisfeed:v1.0.0` | GitHub Container Registry |

Web 镜像拉取运行：

```bash
docker pull ghcr.io/zhruoshui/ferrisfeed:v1.0.0
docker run -p 8080:80 ghcr.io/zhruoshui/ferrisfeed:v1.0.0
```

## 需要配置的 Secrets

在仓库 **Settings → Secrets and variables → Actions** 添加以下 4 个，用于 Android 签名（与 `android/app/build.gradle.kts` 读取的环境变量对应）：

| Secret | 说明 |
|--------|------|
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 base64：`base64 -w0 your.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码（store password） |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

> Web 推送到 ghcr.io 使用内置 `GITHUB_TOKEN`，无需额外配置。首次发布后，到仓库 **Packages** 页可把镜像可见性改为 public。

## 备注

- Flutter 固定 `3.44.1`（与 `.fvmrc` 一致），Rust 原生库由 cargokit 在 `flutter build` 时自动交叉编译。
- Web 镜像由 `Dockerfile.web` 构建，其内部自带 Flutter / flutter_rust_bridge 版本与 nightly Rust 工具链，构建自包含。
- 各 job 独立，单端失败不影响其它端产物；`release` job 汇总附件并创建/更新 Release。
