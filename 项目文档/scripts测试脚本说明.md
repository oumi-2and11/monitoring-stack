# 测试脚本说明

项目 `scripts/` 目录下共 5 个 PowerShell 脚本，分别用于启动/停止服务、触发告警、动态服务发现演示。

---

## 一、up.ps1 — 一键启动

```powershell
.\scripts\up.ps1
```

### 作用

启动 monitoring-stack 全部 7 个服务，等待就绪后检查各服务健康状态。

### 工作原理

1. 定位到项目根目录（通过 `$PSScriptRoot` 向上一级）
2. 执行 `docker compose up -d --build`：
   - `-d`：后台运行容器
   - `--build`：对有 Dockerfile 的服务（flask_app、alert_receiver）重新构建镜像
3. 等待 10 秒让容器完成初始化
4. 逐个 HTTP 探测各服务端口，输出状态

### 注意事项

- 运行前确保 Docker Desktop 已启动
- 首次运行需拉取镜像，约 2-5 分钟
- 后续启动只需几秒（镜像已缓存）

---

## 二、down.ps1 — 一键停止

```powershell
# 停止但保留数据
.\scripts\down.ps1

# 停止并清除所有数据（下次启动如全新环境）
.\scripts\down.ps1 -Clean
```

### 作用

停止全部容器。加 `-Clean` 参数同时删除 Docker volumes（Prometheus/Grafana/Alertmanager 的历史数据）。

### 工作原理

1. 定位到项目根目录
2. 不加 `-Clean`：执行 `docker compose down`，停止并删除容器，保留 volumes
3. 加 `-Clean`：执行 `docker compose down -v`，停止容器并删除 volumes
   - 删除 `prometheus_data`、`grafana_data`、`alertmanager_data` 三个命名 volume
   - 下次 `up` 后 Grafana 恢复默认 admin/admin 密码，Dashboard 通过 Provisioning 重新加载
   - Prometheus 历史时序数据清空，从零开始采集

### 什么时候用 -Clean

- 忘记 Grafana 密码时
- 数据异常需要完全重置时
- 交付前演示确保干净环境时

---

## 三、trigger_error.ps1 — 触发错误率告警

```powershell
.\scripts\trigger_error.ps1
```

### 作用

循环调用 Flask `/error` 接口，拉高 5xx 错误率，触发 `FlaskAppErrorRateHigh` 告警。

### 工作原理

1. 以 200ms 间隔循环调用 `http://localhost:8000/error`
   - 每次调用使 `flask_http_request_total{endpoint="/error",status_code="500"}` Counter +1
2. 每 5 次请求混入 1 次正常请求（调用 `/`）
   - 使错误率约为 80%，而非 100%
   - 为什么不 100%：如果所有请求都是 500，PromQL 的 `rate(5xx) / rate(all)` 分母和分子相同标签会匹配不正确，混入正常请求保证分母有数据
3. 默认运行 120 秒（2 分钟）
4. 可随时按 Ctrl+C 提前停止

### 触发条件

告警规则 `FlaskAppErrorRateHigh` 的条件是：5xx 错误率 > 5% 且持续 1 分钟。脚本以约 80% 的错误率持续发送请求，约 1 分钟后告警从 INACTIVE → FIRING。

### 观察方法

1. Prometheus Alerts：http://localhost:9090/alerts，`FlaskAppErrorRateHigh` 变红
2. Alertmanager：http://localhost:9093，出现 active 告警
3. Alert Receiver：http://localhost:5001，表格显示告警记录
4. Grafana Flask Dashboard：Error Rate 仪表盘上升，Alert Status 变 FIRING

### 停止后恢复

停止脚本后约 1-2 分钟，Flask 不再收到 `/error` 请求，错误率降至 0，告警自动 RESOLVED。

---

## 四、trigger_latency.ps1 — 触发延迟上升

```powershell
.\scripts\trigger_latency.ps1
```

### 作用

循环调用 Flask `/slow` 接口，模拟高延迟请求，观察延迟分位数变化。

### 工作原理

1. 循环调用 `http://localhost:8000/slow`
   - `/slow` 接口内部执行 `time.sleep(random.uniform(0.5, 3.0))`，随机延迟 0.5~3.0 秒
   - 每次调用使 `flask_http_request_total{endpoint="/slow",status_code="200"}` Counter +1
   - `flask_http_request_duration_seconds` Histogram 记录包含 sleep 时间的完整延迟
2. 默认运行 120 秒（2 分钟）
3. 控制台实时打印每次请求的实际延迟

### 观察方法

在 Grafana Flask Service Overview Dashboard 中：
- Request Latency (P50/P95/P99)：P95/P99 明显上升（/slow 的延迟拉高尾部）
- Request Latency by Endpoint：`/slow` 的 P95 远高于 `/` 和 `/error`
- 脚本停止后延迟逐渐恢复正常

### 与 trigger_error 的区别

| | trigger_error.ps1 | trigger_latency.ps1 |
|---|---|---|
| 调用接口 | `/error`（500） | `/slow`（200，延迟） |
| 影响指标 | 错误率上升 | 延迟分位数上升 |
| 是否触发告警 | 触发 FlaskAppErrorRateHigh | 不直接触发告警（无延迟告警规则） |
| 混入正常请求 | 是（1/5 比例） | 否 |

---

## 五、add_target.ps1 — 动态追加服务发现目标

```powershell
.\scripts\add_target.ps1 -Target "prometheus:9090"
.\scripts\add_target.ps1 -Target "192.168.1.100:9100"
```

### 作用

向 Prometheus 的 file_sd 动态发现配置文件 `targets.json` 中追加一个新的采集目标。

### 工作原理

1. 读取 `prometheus/file_sd/targets.json` 文件
2. 用 `ConvertFrom-Json` 解析为 PowerShell 对象数组
3. 构造新条目：

```json
{
  "labels": { "job": "flask_app_sd", "env": "dynamic" },
  "targets": ["<你传入的地址>"]
}
```

4. 追加到数组末尾
5. 用 `ConvertTo-Json` 序列化后写回文件
6. **关键细节**：使用 .NET 的 `[System.IO.File]::WriteAllText()` 配合 `[System.Text.UTF8Encoding]::new($false)` 写入 UTF-8 无 BOM 编码
   - PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会添加 BOM（字节顺序标记 EF BB BF）
   - Prometheus 解析 JSON 时遇到 BOM 会报错 `invalid character 'ï'`
   - 所以必须用 .NET API 显式指定无 BOM

### 生效机制

Prometheus 的 `file_sd_configs` 配置了 `refresh_interval: 30s`，每 30 秒重新读取 `targets.json`。文件内容变化后，新目标在 30 秒内自动出现在 `/targets` 页面并开始被采集，无需修改 prometheus.yml 或重启 Prometheus。

### 注意事项

- `-Target` 参数格式为 `host:port`，其中 host 为 Docker 网络内的服务名（如 `flask_app`）或 IP
- 新追加的目标必须从 Prometheus 容器内部可达（在同一 `monitoring-net` 网络中）
- 多次运行会持续追加条目，不会去重
- 如需清空，直接编辑 `prometheus/file_sd/targets.json` 恢复为初始内容
