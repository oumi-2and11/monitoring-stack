from locust import HttpUser, task, between


class MonitoringUser(HttpUser):
    wait_time = between(0.5, 2)

    @task(8)
    def index(self):
        self.client.get("/")

    @task(1)
    def error(self):
        self.client.get("/error")

    @task(1)
    def slow(self):
        self.client.get("/slow")
