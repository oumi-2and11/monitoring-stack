import json
from datetime import datetime
from flask import Flask, request, jsonify, render_template_string

app = Flask(__name__)

alerts = []


@app.route("/webhook", methods=["POST"])
def webhook():
    data = request.json
    for alert in data.get("alerts", []):
        alerts.append(
            {
                "received_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "status": alert.get("status"),
                "alertname": alert.get("labels", {}).get("alertname"),
                "severity": alert.get("labels", {}).get("severity"),
                "instance": alert.get("labels", {}).get("instance", "N/A"),
                "summary": alert.get("annotations", {}).get("summary", ""),
                "description": alert.get("annotations", {}).get("description", ""),
                "starts_at": alert.get("startsAt"),
                "ends_at": alert.get("endsAt"),
            }
        )
    print(f"Received {len(data.get('alerts', []))} alert(s), total: {len(alerts)}")
    return jsonify(status="ok")


PAGE_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Alert Receiver</title>
    <style>
        body { font-family: -apple-system, sans-serif; margin: 2rem; background: #1a1a2e; color: #e0e0e0; }
        h1 { color: #e94560; }
        h2 { color: #0f3460; background: #e94560; display: inline-block; padding: 4px 12px; border-radius: 4px; }
        table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
        th, td { border: 1px solid #333; padding: 8px 12px; text-align: left; }
        th { background: #16213e; color: #e94560; }
        tr:nth-child(even) { background: #16213e; }
        .firing { color: #e94560; font-weight: bold; }
        .resolved { color: #00e676; }
        .badge { padding: 2px 8px; border-radius: 4px; font-size: 0.85em; }
        .critical { background: #e94560; color: white; }
        .warning { background: #ff9800; color: white; }
        .empty { text-align: center; padding: 3rem; color: #666; }
    </style>
</head>
<body>
    <h1>Alert Receiver - Webhook Dashboard</h1>
    <p>Total alerts received: {{ alerts|length }}</p>
    {% if alerts %}
    <table>
        <tr>
            <th>#</th>
            <th>Time</th>
            <th>Status</th>
            <th>Alert</th>
            <th>Severity</th>
            <th>Instance</th>
            <th>Summary</th>
        </tr>
        {% for a in alerts|reverse %}
        <tr>
            <td>{{ loop.index }}</td>
            <td>{{ a.received_at }}</td>
            <td class="{{ a.status }}">{{ a.status|upper }}</td>
            <td>{{ a.alertname }}</td>
            <td><span class="badge {{ a.severity }}">{{ a.severity }}</span></td>
            <td>{{ a.instance }}</td>
            <td>{{ a.summary }}</td>
        </tr>
        {% endfor %}
    </table>
    {% else %}
    <p class="empty">No alerts received yet. Trigger some alerts to see them here.</p>
    {% endif %}
</body>
</html>
"""


@app.route("/")
def index():
    return render_template_string(PAGE_TEMPLATE, alerts=alerts)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
