# monitoring-stack

基于 Docker 构建的 Prometheus + Grafana 监控告警集群，网络空间安全编程技术与实例开发课程期末大作业。

## 快速启动

```powershell
# 前提：Docker Desktop 正在运行
docker compose up -d --build

# 确认所有服务正常
docker compose ps
```

启动后访问 http://localhost:3000（admin/admin）即可看到监控面板。

## 服务一览

| 服务 | 端口 | 说明 |
|---|---|---|
| Prometheus | http://localhost:9090 | 采集引擎，5 个采集目标，5 条告警规则 |
| Grafana | http://localhost:3000 | 可视化面板，2 个 Dashboard 共 13 个面板，自动加载 |
| Alertmanager | http://localhost:9093 | 告警路由与通知，按 job 分组推送到 webhook |
| Flask 被测服务 | http://localhost:8000 | 自研服务，暴露 Counter + Histogram 自定义指标 |
| Alert Receiver | http://localhost:5001 | 自研告警接收器，展示告警记录表格 |
| cAdvisor | http://localhost:8080 | 容器 CPU/内存指标 |
| Node Exporter | http://localhost:9100/metrics | 主机 CPU/内存/磁盘/网络指标 |

## 项目结构

```
monitoring-stack/
├── docker-compose.yml                 # 7 个服务编排
├── prometheus/
│   ├── prometheus.yml                 # 采集配置（静态 + file_sd 动态发现）
│   ├── rules/alerts.yml               # 5 条告警规则
│   └── file_sd/targets.json           # 动态发现目标文件
├── alertmanager/
│   └── alertmanager.yml               # 告警路由/分组/webhook 配置
├── grafana/
│   ├── provisioning/                  # 数据源 + Dashboard 自动加载
│   └── dashboards/                    # 2 个 Dashboard JSON
├── services/
│   ├── flask_app/                     # Flask 被测服务 + 指标
│   │   ├── app.py
│   │   ├── templates/                 # 前端页面模板
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   └── alert_receiver/               # 告警 webhook 接收器
│       ├── app.py
│       ├── Dockerfile
│       └── requirements.txt
├── loadtest/
│   └── locustfile.py                  # Locust 压测脚本
├── scripts/
│   ├── up.ps1                         # 一键启动
│   ├── down.ps1                       # 一键停止（-Clean 清除数据）
│   ├── trigger_error.ps1              # 触发错误率告警
│   ├── trigger_latency.ps1            # 触发延迟上升
│   └── add_target.ps1                 # 动态追加服务发现目标
└── 项目文档/
    ├── 项目文件架构.md
    ├── 实现计划.md
    ├── 项目使用说明.md
    ├── Prometheus采集系统设计.md
    ├── Grafana Dashboard面板设计.md
    ├── 接口文档.md
    └── scripts测试脚本说明.md
```

## 核心功能

### 采集层

- **node_exporter** — 主机 CPU、内存、磁盘、网络指标
- **cAdvisor** — 容器 CPU、内存、生命周期指标
- **Flask 自研服务** — 请求总数 Counter、延迟 Histogram
- **Prometheus 自监控** — 采集引擎自身运行指标

### 服务发现

- **静态发现**（static_configs）— prometheus、node_exporter、cadvisor、flask_app，地址固定写在配置文件中
- **动态发现**（file_sd_configs）— flask_app_sd，读取 targets.json，30 秒自动刷新，无需重启

### 告警体系

| 规则 | 条件 | 持续时间 | 级别 |
|---|---|---|---|
| HostHighCpuLoad | CPU > 80% | 1m | warning |
| HostHighMemoryUsage | 内存 > 90% | 2m | warning |
| FlaskAppErrorRateHigh | 5xx 错误率 > 5% | 1m | critical |
| ContainerHighCpu | 容器 CPU > 80% | 2m | warning |
| ContainerRestartCount | 10m 内重启 > 3 次 | 0m | critical |

告警流程：Prometheus 评估规则 → Alertmanager 分组路由 → Webhook 推送 → Alert Receiver 展示

### 安全加固

- Docker `monitoring-net` 桥接网络隔离，容器间仅通过内部网络通信
- Grafana Admin + Viewer 双角色，Viewer 只读
- 告警规则作为安全事件间接检测（异常重启、错误率突增）

## 告警演示

```powershell
# 触发错误率告警
.\scripts\trigger_error.ps1

# 观察全链路：
# 1. Prometheus /alerts → FlaskAppErrorRateHigh 变红 FIRING
# 2. Alertmanager:9093 → 出现 active 告警
# 3. Alert Receiver:5001 → 显示告警记录
# 4. Grafana Flask Dashboard → 错误率上升，Alert Status 变 FIRING
```

停止脚本后约 1-2 分钟告警自动恢复（RESOLVED）。

## 压测

```powershell
.venv\Scripts\python.exe -m locust -f loadtest\locustfile.py --host=http://localhost:8000 --headless -u 30 -r 5 -t 60s --only-summary
```

## 停止

```powershell
docker compose down          # 停止，保留数据
.\scripts\down.ps1 -Clean    # 停止并清除所有数据
```
