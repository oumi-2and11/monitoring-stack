# Prometheus 采集系统设计

## 1. 采集架构概览

Prometheus 作为核心采集引擎，采用 Pull 模式定期从各 Exporter 拉取指标数据。整个采集系统由 5 个 scrape job 组成，覆盖自监控、主机、容器、业务服务四个层面，并支持静态配置与动态服务发现两种方式。

```
Prometheus (采集引擎)
  ├── prometheus    (自监控)      ← static_configs
  ├── node_exporter (主机指标)    ← static_configs
  ├── cadvisor      (容器指标)    ← static_configs
  ├── flask_app     (业务指标)    ← static_configs
  └── flask_app_sd  (业务指标)    ← file_sd_configs (动态发现)
```

采集全局配置：

- `scrape_interval: 15s` — 每 15 秒采集一次
- `evaluation_interval: 15s` — 每 15 秒评估一次告警规则

---

## 2. 各采集目标详解

### 2.1 Prometheus 自监控

| 配置项 | 值 |
|---|---|
| job_name | `prometheus` |
| 发现方式 | static_configs |
| 目标地址 | `localhost:9090` |
| 采集路径 | `/metrics`（默认） |

Prometheus 采集自身运行指标，用于监控采集引擎本身的健康状态。主要指标包括：

| 指标名 | 类型 | 说明 |
|---|---|---|
| `prometheus_target_scrapes_total` | Counter | 总抓取次数 |
| `prometheus_target_scrape_duration_seconds` | Summary | 每次抓取耗时 |
| `prometheus_target_up` | Gauge | 目标是否可达（1=UP, 0=DOWN） |
| `prometheus_tsdb_head_series` | Gauge | 当前内存中的时间序列数 |
| `prometheus_tsdb_head_chunks` | Gauge | 当前内存中的 chunk 数 |
| `prometheus_rule_evaluation_duration_seconds` | Summary | 规则评估耗时 |
| `up` | Gauge | 采集目标健康状态（1=UP, 0=DOWN） |

`up` 指标是 Prometheus 内置指标，每个 scrape job 都会产生，值为 1 表示目标正常，0 表示抓取失败。它是判断采集系统本身是否正常运转的关键指标。

---

### 2.2 node_exporter — 主机指标

| 配置项 | 值 |
|---|---|
| job_name | `node_exporter` |
| 发现方式 | static_configs |
| 目标地址 | `node_exporter:9100` |
| 采集路径 | `/metrics`（默认） |

node_exporter 采集宿主机（Docker Desktop 运行的 WSL2 Linux 内核）的硬件与操作系统指标，暴露约 284 个 `node_*` 前缀指标。本项目关注以下核心指标：

#### CPU 相关

| 指标名 | 类型 | 说明 |
|---|---|---|
| `node_cpu_seconds_total` | Counter | CPU 各模式（idle/user/system/iowait 等）累计使用秒数 |

**PromQL 计算公式：** `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)` — 计算 CPU 使用率，取 idle 的补数。

#### 内存相关

| 指标名 | 类型 | 说明 |
|---|---|---|
| `node_memory_MemTotal_bytes` | Gauge | 总内存大小 |
| `node_memory_MemAvailable_bytes` | Gauge | 可用内存大小（含缓存可回收部分） |

**PromQL 计算公式：** `100 - (100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)` — 计算内存使用率。使用 `MemAvailable` 而非 `MemFree`，因为后者不包含可回收的缓存。

#### 磁盘相关

| 指标名 | 类型 | 说明 |
|---|---|---|
| `node_filesystem_size_bytes` | Gauge | 文件系统总容量 |
| `node_filesystem_avail_bytes` | Gauge | 文件系统可用空间 |
| `node_filesystem_files` | Gauge | 文件系统 inode 总数 |
| `node_filesystem_files_free` | Gauge | 文件系统空闲 inode 数 |

**PromQL 计算公式：** `100 - (100 * node_filesystem_avail_bytes / node_filesystem_size_bytes)` — 计算磁盘使用率。按 `fstype` 过滤 ext4/vfat/ntfs/overlay 等真实文件系统，排除 tmpfs 等虚拟文件系统。

#### 网络相关

| 指标名 | 类型 | 说明 |
|---|---|---|
| `node_network_receive_bytes_total` | Counter | 网卡接收总字节数 |
| `node_network_transmit_bytes_total` | Counter | 网卡发送总字节数 |
| `node_network_receive_packets_total` | Counter | 网卡接收总包数 |
| `node_network_transmit_packets_total` | Counter | 网卡发送总包数 |

**PromQL 计算公式：** `rate(node_network_receive_bytes_total{device=~"eth.*"}[2m])` — 计算每秒网络流量。按 `device` 过滤 eth 网卡，排除 lo 回环接口。

> **Windows 环境说明：** Docker Desktop 使用 WSL2 后端，容器实际运行在 Linux 内核上，因此使用 node_exporter 采集的是 WSL2 虚拟机的指标。若要在 Windows 宿主机上直接采集，应使用 windows_exporter，其指标命名有差异（如 `windows_cpu_time_total` vs `node_cpu_seconds_total`），PromQL 需适配。

---

### 2.3 cAdvisor — 容器指标

| 配置项 | 值 |
|---|---|
| job_name | `cadvisor` |
| 发现方式 | static_configs |
| 目标地址 | `cadvisor:8080` |
| 采集路径 | `/metrics`（默认） |

cAdvisor（Container Advisor）由 Google 开源，专门采集 Docker 容器的资源使用指标，暴露约 60 个 `container_*` 前缀指标。本项目关注以下核心指标：

#### 容器 CPU

| 指标名 | 类型 | 说明 |
|---|---|---|
| `container_cpu_usage_seconds_total` | Counter | 容器 CPU 累计使用秒数（按 CPU 核编号分） |

**PromQL 计算公式：** `topk(5, (rate(container_cpu_usage_seconds_total{...}[2m])) * 100)` — 取 CPU 使用率 Top5 的容器。通过 `container_label_com_docker_compose_service` 标签过滤出 Docker Compose 管理的容器。

#### 容器内存

| 指标名 | 类型 | 说明 |
|---|---|---|
| `container_memory_usage_bytes` | Gauge | 容器当前内存使用量（含缓存） |
| `container_memory_working_set_bytes` | Gauge | 容器工作集内存（不可被驱逐，更真实反映压力） |
| `container_memory_cache` | Gauge | 容器页面缓存 |

**PromQL 计算公式：** `topk(5, container_memory_usage_bytes{...})` — 取内存使用 Top5 的容器。

#### 容器生命周期

| 指标名 | 类型 | 说明 |
|---|---|---|
| `container_restart_count` | Gauge | 容器重启次数 |
| `container_start_time_seconds` | Gauge | 容器启动时间戳 |
| `container_last_seen` | Gauge | 容器最近一次被 cAdvisor 观测到的时间戳 |

**PromQL 计算公式：** `increase(container_restart_count[10m])` — 计算 10 分钟内的重启增量。异常重启是容器故障和安全事件的重要间接指标。

#### 容器网络

| 指标名 | 类型 | 说明 |
|---|---|---|
| `container_network_receive_bytes_total` | Counter | 容器网络接收总字节 |
| `container_network_transmit_bytes_total` | Counter | 容器网络发送总字节 |

> **WSL2 限制说明：** cAdvisor 在 Windows Docker Desktop (WSL2) 下部分 cgroup 指标可能缺失（如 per-cgroup CPU 限制），这是 WSL2 的已知限制。容器级别的 CPU/内存指标通常正常。

---

### 2.4 Flask 应用 — 业务指标

Flask 应用通过 `prometheus_client` 库暴露自定义业务指标，这是项目自研的采集层。

#### 采集配置（静态发现）

| 配置项 | 值 |
|---|---|
| job_name | `flask_app` |
| 发现方式 | static_configs |
| 目标地址 | `flask_app:8000` |
| 采集路径 | `/metrics`（显式指定） |

#### 采集配置（动态发现）

| 配置项 | 值 |
|---|---|
| job_name | `flask_app_sd` |
| 发现方式 | file_sd_configs |
| 目标文件 | `/etc/prometheus/file_sd/targets.json` |
| 刷新间隔 | `30s` |
| 采集路径 | `/metrics`（显式指定） |

#### 自定义指标

| 指标名 | 类型 | 标签 | 说明 |
|---|---|---|---|
| `flask_http_request_total` | Counter | `method`, `endpoint`, `status_code` | HTTP 请求总数，按方法/端点/状态码分类 |
| `flask_http_request_duration_seconds` | Histogram | `method`, `endpoint` | 请求延迟分布，支持分位数计算 |
| `flask_http_request_duration_seconds_bucket` | — | `method`, `endpoint`, `le` | Histogram 桶计数，用于 `histogram_quantile()` |
| `flask_http_request_duration_seconds_sum` | — | `method`, `endpoint` | 延迟总和 |
| `flask_http_request_duration_seconds_count` | — | `method`, `endpoint` | 延迟观测次数 |

Histogram 桶边界配置：`[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]` 秒，覆盖从 5ms 到 5s 的延迟范围。

**典型 PromQL：**

- QPS：`sum by(status_code) (rate(flask_http_request_total{job="flask_app"}[1m]))`
- 错误率：`(sum(rate(flask_http_request_total{status_code=~"5.."}[1m])) / sum(rate(flask_http_request_total[1m]))) * 100`
- P95 延迟：`histogram_quantile(0.95, sum by(le) (rate(flask_http_request_duration_seconds_bucket[2m])))`

---

## 3. 服务发现方式对比

| 特性 | static_configs | file_sd_configs |
|---|---|---|
| 配置方式 | 在 prometheus.yml 中直接写死目标地址 | 指向外部 JSON 文件，Prometheus 定期刷新 |
| 变更操作 | 修改 prometheus.yml + 重启 Prometheus | 修改 JSON 文件，30s 内自动生效 |
| 适用场景 | 目标地址固定的服务 | 容器环境中实例动态增减的服务 |
| 本项目应用 | prometheus、node_exporter、cadvisor、flask_app | flask_app_sd |
| 运维成本 | 低（简单） | 中（需维护 JSON 文件） |

动态服务发现 JSON 文件格式（`prometheus/file_sd/targets.json`）：

```json
[
  {
    "labels": { "job": "flask_app_sd", "env": "dynamic" },
    "targets": ["flask_app:8000"]
  }
]
```

通过 `scripts/add_target.ps1` 可动态追加目标，Prometheus 在 30 秒 `refresh_interval` 内自动感知变化，无需重启。

---

## 4. 指标与告警规则的关联

采集的指标直接驱动告警规则的评估：

| 告警规则 | 依赖指标 | 采集源 |
|---|---|---|
| HostHighCpuLoad | `node_cpu_seconds_total` | node_exporter |
| HostHighMemoryUsage | `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes` | node_exporter |
| FlaskAppErrorRateHigh | `flask_http_request_total` | Flask 应用 |
| ContainerHighCpu | `container_cpu_usage_seconds_total` | cAdvisor |
| ContainerRestartCount | `container_restart_count` | cAdvisor |

告警评估周期与采集周期一致（`evaluation_interval: 15s`），确保告警能及时反映指标变化。
