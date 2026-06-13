# PetNote Sync Server

自建同步中继服务，负责配对码撮合、WebSocket 在线中转、设备目录、设备在线状态和一期视频信令透传。

## 部署

在仓库根目录执行：

```bash
docker compose -f server/docker-compose.yml up -d --build
```

如果已经构建过镜像，也可以使用 `docker compose up -d` 启动同一组服务。

Compose 的 build context 必须是仓库根目录，因为镜像构建需要同时复制 `server/` 与 `packages/petnote_sync_protocol/`。

## 反代 TLS

建议由 Caddy 或 nginx 负责 TLS，服务本身监听 `8787`：

```caddyfile
your.domain {
  reverse_proxy localhost:8787
}
```

App 内同步服务器地址填写：

```text
wss://your.domain/ws
```

## 阿里云 Linux 3 接入

服务器域名 `petnote.juren233.top` 指向 ECS 公网 IP 后，先在安全组放行 `80`、`443`，再安装 Docker 和 Compose 插件：

```bash
sudo dnf update -y
sudo dnf install -y docker docker-compose-plugin git
sudo systemctl enable --now docker
```

把仓库放到服务器后，在仓库根目录启动同步服务：

```bash
docker compose -f server/docker-compose.yml up -d --build
docker compose -f server/docker-compose.yml ps
curl http://127.0.0.1:8787/healthz
```

如果使用 Caddy 自动签发证书：

```bash
sudo dnf install -y 'dnf-command(copr)'
sudo dnf copr enable @caddy/caddy -y
sudo dnf install -y caddy
```

`/etc/caddy/Caddyfile`：

```caddyfile
petnote.juren233.top {
  reverse_proxy 127.0.0.1:8787
}
```

```bash
sudo systemctl enable --now caddy
sudo systemctl reload caddy
curl https://petnote.juren233.top/healthz
```

官方服务器配置端点 `petnote-server.juren233.top` 需要返回当前同步服务器域名或 WebSocket 地址。App 会读取 `https://petnote-server.juren233.top/server`，推荐返回：

```json
{
  "server_domain": "petnote.juren233.top",
  "server_url": "wss://petnote.juren233.top/ws"
}
```

## 数据与备份

运行数据写入容器内 `/data`，Compose 默认挂载到 `petnote-data` volume。迁移或重装服务器前请备份该 volume，里面包含 household、认证 token、配对盐值和设备目录。

业务快照和待办 / 提醒操作会在线中转；服务器会持久化未完成回执的同步事件、完成状态否决账本和设备回执标记，用于服务重启后继续补发离线设备尚未收到的数据。所有当前设备都回传 `sync_received` 后，对应同步事件会从账本清理。

## TURN 预留

`docker-compose.yml` 中保留了注释状态的 `coturn` 服务。二期接入 WebRTC 时再启用 TURN 凭证下发和客户端 RTC 逻辑，本期不接音视频媒体流。
