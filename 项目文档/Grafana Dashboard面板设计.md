# Grafana Dashboard 面板设计

## 1. 总体说明

项目通过 Grafana Provisioning 机制自动加载 2 个 Dashboard，共 13 个面板，无需任何手动配置。

| Dashboard | 面板数 | 数据来源 | 关注领域 |
|---|---|---|---|
| Host & Docker Overview | 7 | node_exporter + cAdvisor | 基础设施层：主机资源 + 容器资源 |
| Flask Service Overview | 6 | Flask 应用指标 | 业务层：请求量/错误率/延迟/告警 |

两个 Dashboard 均使用模板变量 `DS_PROMETHEUS` 引用数据源，默认时间范围 `now-15m` 到 `now`。

---

## 2. Dashboard 1：Host & Docker Overview

**文件：** `grafana/dashboards/01-host-and-docker.json`
**UID：** `host-docker-overview`
**标签：** host, docker, node_exporter, cadvisor

### 面板布局

```
┌─────────────────────┐  ┌─────────────────────┐
│  CPU Usage (%)      │  │  Memory Usage (%)    │  y=0
│  timeseries         │  │  timeseries          │
├─────────────────────┤  ├─────────────────────┤
│  Disk Usage (%)     │  │  Network I/O         │  y=8
│  timeseries         │  │  timeseries          │
├─────────────────────┤  ├─────────────────────┤
│  Container CPU Top5 │  │  Container Mem Top5  │  y=16
│  barchart           │  │  barchart            │
├─────────────────────┴──┴─────────────────────┤
│  Container Restart Count        stat          │  y=24
└───────────────────────────────────────────────┘
```

### 面板 1：CPU Usage (%)

| 属性 | 值 |
|---|---|
| 类型 | timeseries（时间序列折线图） |
| 位置 | (0,0) — 左上角，宽12高8 |
| 单位 | percent，范围 0–100 |
| 数据源 | node_exporter |

**PromQL：**

```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
```

**说明：** 计算主机 CPU 使用率。`rate()` 取 idle 模式 CPU 时间的 2 分钟增速，`avg by(instance)` 按实例平均（多核合并），100 减去 idle 比例即为使用率。图例按实例名显示。

---

### 面板 2：Memory Usage (%)

| 属性 | 值 |
|---|---|
| 类型 | timeseries |
| 位置 | (12,0) — 右上角，宽12高8 |
| 单位 | percent，范围 0–100 |
| 数据源 | node_exporter |

**PromQL：**

```promql
100 - (100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

**说明：** 计算主机内存使用率。`MemAvailable` 包含可回收缓存，比 `MemFree` 更准确地反映真实内存压力。

---

### 面板 3：Disk Usage (%)

| 属性 | 值 |
|---|---|
| 类型 | timeseries |
| 位置 | (0,8) — 左中，宽12高8 |
| 单位 | percent，范围 0–100 |
| 数据源 | node_exporter |

**PromQL：**

```promql
100 - (100 * node_filesystem_avail_bytes{fstype=~"ext4|vfat|ntfs|overlay"} / node_filesystem_size_bytes{fstype=~"ext4|vfat|ntfs|overlay"})
```

**说明：** 计算各文件系统挂载点的磁盘使用率。按 `fstype` 过滤真实文件系统类型，排除 tmpfs/procfs 等虚拟文件系统。图例显示实例名+挂载点路径。

---

### 面板 4：Network I/O (bytes/sec)

| 属性 | 值 |
|---|---|
| 类型 | timeseries |
| 位置 | (12,8) — 右中，宽12高8 |
| 单位 | Bps（字节/秒） |
| 数据源 | node_exporter |

**PromQL：**

```promql
# 接收（RX）
rate(node_network_receive_bytes_total{device=~"eth.*"}[2m])
# 发送（TX）
rate(node_network_transmit_bytes_total{device=~"eth.*"}[2m])
```

**说明：** 展示主机网络吞吐量。两条查询分别绘制接收和发送速率，按 `device` 过滤 eth 网卡排除回环接口。图例前缀 RX/TX 区分方向。

---

### 面板 5：Container CPU Top5 (%)

| 属性 | 值 |
|---|---|
| 类型 | barchart（柱状图） |
| 位置 | (0,16) — 左下，宽12高8 |
| 单位 | percent |
| 数据源 | cAdvisor |

**PromQL：**

```promql
topk(5, (rate(container_cpu_usage_seconds_total{container_label_com_docker_compose_service!=""}[2m])) * 100)
```

**说明：** 取 CPU 使用率最高的 5 个容器，以柱状图直观对比。通过 `container_label_com_docker_compose_service` 标签过滤出 Compose 管理的容器，图例显示服务名。

---

### 面板 6：Container Memory Top5

| 属性 | 值 |
|---|---|
| 类型 | barchart |
| 位置 | (12,16) — 右下，宽12高8 |
| 单位 | bytes |
| 数据源 | cAdvisor |

**PromQL：**

```promql
topk(5, container_memory_usage_bytes{container_label_com_docker_compose_service!=""})
```

**说明：** 取内存使用量最高的 5 个容器，柱状图对比。与面板 5 对称布局，方便同时观察 CPU 和内存 Top 消耗者。

---

### 面板 7：Container Restart Count

| 属性 | 值 |
|---|---|
| 类型 | stat（统计值面板） |
| 位置 | (0,24) — 底部通栏，宽24高4 |
| 阈值 | 绿色(0) → 黄色(≥1) → 红色(≥3) |
| 数据源 | cAdvisor |

**PromQL：**

```promql
increase(container_restart_count[10m])
```

**说明：** 统计 10 分钟内各容器重启次数。使用颜色阈值：0 次绿色正常、1-2 次黄色警告、3 次以上红色告警。异常重启是容器崩溃和安全事件的间接指标，此面板跨全宽放置以突出显示。

---

## 3. Dashboard 2：Flask Service Overview

**文件：** `grafana/dashboards/02-flask-service.json`
**UID：** `flask-service-overview`
**标签：** flask, service, business

### 面板布局

```
┌─────────────────────┐  ┌────────┐  ┌────────┐
│  Request QPS        │  │  Error │  │ Total  │  y=0
│  (by status code)   │  │  Rate  │  │  Reqs  │
│  timeseries         │  │  gauge │  │  stat  │
├─────────────────────┤  ├────────┴──┴────────┤
│  Latency            │  │  Latency by         │  y=9
│  P50/P95/P99        │  │  Endpoint           │
│  timeseries         │  │  timeseries         │
├─────────────────────┴──┴─────────────────────┤
│  Alert Status                     stat         │  y=18
└───────────────────────────────────────────────┘
```

### 面板 1：Request QPS (by status code)

| 属性 | 值 |
|---|---|
| 类型 | timeseries |
| 位置 | (0,0) — 左上，宽12高9 |
| 单位 | reqps（请求/秒） |
| 数据源 | Flask 应用 |

**PromQL：**

```promql
sum by(status_code) (rate(flask_http_request_total{job="flask_app"}[1m]))
```

**说明：** 按状态码分类展示 Flask 服务的每秒请求数。正常情况下 200 状态码占主导；运行 `trigger_error.ps1` 后可观察到 500 状态码的 QPS 上升。此面板是业务流量的核心视图。

---

### 面板 2：Error Rate (%)

| 属性 | 值 |
|---|---|
| 类型 | gauge（仪表盘） |
| 位置 | (12,0) — 中上，宽6高9 |
| 单位 | percent，范围 0–100 |
| 阈值 | 绿色(0–5%) → 黄色(5–20%) → 红色(>20%) |
| 数据源 | Flask 应用 |

**PromQL：**

```promql
(sum(rate(flask_http_request_total{job="flask_app",status_code=~"5.."}[1m])) / sum(rate(flask_http_request_total{job="flask_app"}[1m]))) * 100
```

**说明：** 计算 5xx 错误率百分比，以仪表盘形式直观展示。阈值与告警规则 `FlaskAppErrorRateHigh` 的 5% 阈值对齐：5% 以下绿色正常，5-20% 黄色警告，20% 以上红色严重。这是整个监控系统最关键的业务健康指标。

---

### 面板 3：Total Requests

| 属性 | 值 |
|---|---|
| 类型 | stat |
| 位置 | (18,0) — 右上，宽6高9 |
| 单位 | short（整数） |
| 数据源 | Flask 应用 |

**PromQL：**

```promql
sum(flask_http_request_total{job="flask_app"})
```

**说明：** 显示 Flask 服务自启动以来的请求总数。与 Error Rate 面板并列，提供"总量+质量"的完整视图。

---

### 面板 4：Request Latency (P50 / P95 / P99)

| 属性 | 值 |
|---|---|
| 类型 | timeseries |
| 位置 | (0,9) — 左中，宽12高9 |
| 单位 | s（秒） |
| 数据源 | Flask 应用 |

**PromQL：**

```promql
histogram_quantile(0.50, sum by(le) (rate(flask_http_request_duration_seconds_bucket{job="flask_app"}[2m])))
histogram_quantile(0.95, sum by(le) (rate(flask_http_request_duration_seconds_bucket{job="flask_app"}[2m])))
histogram_quantile(0.99, sum by(le) (rate(flask_http_request_duration_seconds_bucket{job="flask_app"}[2m])))
```

**说明：** 展示请求延迟的三个关键分位数。P50（中位数）反映典型响应速度，P95 反映大多数用户体验，P99 反映尾部延迟（最慢 1% 的请求）。三条线同时展示，可直观判断延迟分布形态。`/slow` 接口会显著推高 P95/P99。

---

### 面板 5：Request Latency by Endpoint

| 属性 | 值 |
|---|---|
| 类型 | timeseries |
| 位置 | (12,9) — 右中，宽12高9 |
| 单位 | s（秒） |
| 数据源 | Flask 应用 |

**PromQL：**

```promql
histogram_quantile(0.95, sum by(le,endpoint) (rate(flask_http_request_duration_seconds_bucket{job="flask_app"}[2m])))
```

**说明：** 按端点分别展示 P95 延迟。对比 `/`、`/error`、`/slow` 三个接口的延迟特征：`/` 正常快速响应，`/error` 立即返回 500，`/slow` 因 `time.sleep()` 产生 0.5–3.0 秒的延迟。此面板帮助定位性能瓶颈的具体端点。

---

### 面板 6：Alert Status

| 属性 | 值 |
|---|---|
| 类型 | stat |
| 位置 | (0,18) — 底部通栏，宽24高5 |
| 映射 | 0 → "OK"(绿色)，1 → "FIRING"(红色) |
| 数据源 | Prometheus 内置 ALERTS 指标 |

**PromQL：**

```promql
count(ALERTS{alertname="FlaskAppErrorRateHigh",alertstate="firing"}) or vector(0)
```

**说明：** 显示 `FlaskAppErrorRateHigh` 告警的当前状态。`ALERTS` 是 Prometheus 内置指标，当告警处于 FIRING 状态时值为 1。通过 `count()` 统计 FIRING 数量，`or vector(0)` 确保无告警时显示 0 而非 No Data。面板用文字映射将 0 显示为绿色 "OK"，1 显示为红色 "FIRING"，实现告警状态在 Dashboard 中的可视化。跨全宽放置以确保醒目。

---

## 4. 面板设计原则

1. **分层覆盖**：Dashboard 1 覆盖基础设施层（主机+容器），Dashboard 2 覆盖业务层（请求/错误/延迟/告警），两层形成完整监控视角
2. **关键指标突出**：Error Rate 使用 gauge 仪表盘、Alert Status 跨全宽、Restart Count 使用颜色阈值，确保异常状态一目了然
3. **关联告警规则**：Error Rate 阈值（5%）与 `FlaskAppErrorRateHigh` 告警阈值对齐，Alert Status 直接展示告警状态，Dashboard 与告警体系联动
4. **Provisioning 自动化**：两个 Dashboard 通过 JSON 文件 + providers.yml 自动加载，老师无需手动导入
