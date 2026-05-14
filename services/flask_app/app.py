import time
import random
from flask import Flask, Response, render_template
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

REQUEST_COUNT = Counter(
    "flask_http_request_total",
    "Total request count",
    ["method", "endpoint", "status_code"],
)

REQUEST_LATENCY = Histogram(
    "flask_http_request_duration_seconds",
    "Request latency in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)


@app.route("/")
def index():
    with REQUEST_LATENCY.labels("GET", "/").time():
        REQUEST_COUNT.labels("GET", "/", "200").inc()
        return render_template("home.html", active="home")


@app.route("/error")
def error():
    with REQUEST_LATENCY.labels("GET", "/error").time():
        REQUEST_COUNT.labels("GET", "/error", "500").inc()
        return render_template("error.html", active="error"), 500


@app.route("/slow")
def slow():
    delay = random.uniform(0.5, 3.0)
    with REQUEST_LATENCY.labels("GET", "/slow").time():
        time.sleep(delay)
        REQUEST_COUNT.labels("GET", "/slow", "200").inc()
        return render_template("slow.html", active="slow", delay=round(delay, 2))


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)