import subprocess
import os
import time
import sys
import threading

# --- Path Setup to import 'utils' from parent directory ---
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.append(parent_dir)

from utils.logger import Logger

# --- Configuration ---
PROJECT_ROOT = parent_dir
K8S_DIR = os.path.join(PROJECT_ROOT, "k8s")


def discover_services():
    """Discover services by finding subdirectories that contain a Dockerfile."""
    services = []
    for name in os.listdir(PROJECT_ROOT):
        path = os.path.join(PROJECT_ROOT, name)
        if os.path.isdir(path) and os.path.isfile(os.path.join(path, "Dockerfile")):
            services.append(name)
    return services


class InfrastructureManager:
    def __init__(self):
        self.env = os.environ.copy()
        self.services = discover_services()
        self._terraform_error = None
        self.minikube_ip = None

    def run_cmd(self, cmd, shell=False, capture=True, cwd_override=None):
        """Helper to run shell commands."""
        cmd_str = cmd if isinstance(cmd, str) else " ".join(cmd)
        Logger.debug(f"Exec: {cmd_str}")

        try:
            result = subprocess.run(
                cmd,
                shell=shell,
                check=True,
                stdout=subprocess.PIPE if capture else None,
                stderr=subprocess.PIPE if capture else None,
                env=self.env,
                cwd=cwd_override or PROJECT_ROOT,
                text=True,
            )
            return result.stdout.strip() if capture else ""
        except subprocess.CalledProcessError as e:
            Logger.error(f"Command failed: {cmd_str}")
            if capture and e.stderr:
                print(e.stderr)
            sys.exit(1)

    # ---------------- Minikube handling ---------------- #

    def check_minikube(self):
        Logger.header("Step 1: Checking Infrastructure")

        # Try status first
        try:
            result = subprocess.run(
                ["minikube", "status"],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if result.returncode == 0 and "Running" in result.stdout:
                Logger.success("Minikube is already running.")
            else:
                Logger.warning("Minikube is NOT running. Starting it now (this may take a while)...")
                subprocess.run(["minikube", "start"], check=True)
                Logger.success("Minikube started successfully.")
        except Exception as e:
            Logger.error(f"Minikube status/start failed: {e}")
            sys.exit(1)

        # Get and store Minikube IP
        try:
            ip = subprocess.check_output(["minikube", "ip"], text=True).strip()
            self.minikube_ip = ip
            Logger.info(f"Minikube IP: {ip}")
        except Exception as e:
            Logger.error(f"Failed to get Minikube IP: {e}")
            self.minikube_ip = "<minikube-ip>"

    # ---------------- Docker env ---------------- #

    def set_docker_env(self):
        Logger.header("Step 2: Configuring Docker Environment")

        try:
            # Use bash shell for Unix systems (macOS/Linux)
            output = subprocess.check_output(
                ["minikube", "-p", "minikube", "docker-env", "--shell", "bash"],
                text=True,
            )

            for line in output.splitlines():
                line = line.strip()
                if line.startswith("export DOCKER_HOST"):
                    value = line.split("=", 1)[1].strip().strip('"\'')
                    self.env["DOCKER_HOST"] = value
                elif line.startswith("export DOCKER_TLS_VERIFY"):
                    value = line.split("=", 1)[1].strip().strip('"\'')
                    self.env["DOCKER_TLS_VERIFY"] = value
                elif line.startswith("export DOCKER_CERT_PATH"):
                    value = line.split("=", 1)[1].strip().strip('"\'')
                    self.env["DOCKER_CERT_PATH"] = value

            Logger.info(f"Pointing Docker to Minikube: {self.env.get('DOCKER_HOST', 'not set')}")
        except Exception as e:
            Logger.error(f"Failed to configure Docker environment: {e}")

    # ---------------- K8s / build / deploy ---------------- #

    def check_if_deployed(self):
        Logger.header("Step 3: Checking Existing Deployments")
        try:
            output = self.run_cmd(["kubectl", "get", "deployments"])
            if "backend-deployment" in output:
                Logger.info("Existing deployments found.")
                return True
        except Exception:
            pass
        Logger.info("No existing deployments found.")
        return False

    def build_images(self):
        Logger.header("Step 4: Building Service Images")
        for service in self.services:
            Logger.info(f"Building image for: {service}...")
            cmd = ["docker", "build", "-t", f"{service}-service:latest", f"./{service}"]
            self.run_cmd(cmd)
            Logger.success(f"Built {service}-service:latest")
        Logger.success("All images built successfully.")

    def _terraform_apply_worker(self, terraform_dir):
        """Run terraform apply; record error but do not crash main thread."""
        try:
            self.run_cmd(["terraform", "init"], cwd_override=terraform_dir)
            self.run_cmd(["terraform", "apply", "-auto-approve"], cwd_override=terraform_dir)
            Logger.success("Terraform apply completed for local manifests.")
        except SystemExit as e:
            self._terraform_error = e

    def deploy_k8s(self):
        Logger.header("Step 5: Deploying via Terraform")

        terraform_dir = os.path.join(PROJECT_ROOT, "terraform", "local")

        # Run terraform in background but still let health-check notice failure
        t = threading.Thread(target=self._terraform_apply_worker, args=(terraform_dir,), daemon=True)
        t.start()

        Logger.info("Terraform apply started in background; waiting for resources to become Ready...")

    def wait_for_pods(self):
        Logger.header("Step 6: Health Check")
        Logger.info("Waiting for Pods to be ready...")

        retries = 0
        max_retries = 40

        while retries < max_retries:
            if self._terraform_error is not None:
                Logger.error("Terraform failed in background; aborting.")
                sys.exit(1)

            output = self.run_cmd(["kubectl", "get", "pods"])
            lines = output.splitlines()
            not_ready_count = 0

            for line in lines[1:]:
                if "Running" not in line:
                    not_ready_count += 1

            if not_ready_count == 0 and len(lines) > 1:
                Logger.success("All Pods are RUNNING (or current state is stable)!")
                return

            time.sleep(3)
            retries += 1
            if retries % 5 == 0:
                Logger.debug("Still waiting for pods...")

        Logger.warning("Timed out waiting for pods. They might still be starting. Check 'kubectl get pods'.")

    def show_access_urls(self):
        Logger.header("Step 7: Access Points")

        ip = self.minikube_ip or "<minikube-ip>"
        ingress_url = f"http://{ip}:32080/"

        print(f"   Ingress HTTP:  {Logger.BOLD}{ingress_url}{Logger.RESET}   # UI at '/', backend under '/api'")
        print("")
        print("Or use port-forward if needed (optional):")
        print("  UI:      kubectl port-forward svc/ui-service 8082:80        # http://localhost:8082")
        print("  Jenkins: kubectl port-forward svc/jenkins-service 8083:8080  # http://localhost:8083")

    # ---------------- Main ---------------- #

    def main(self):
        self.check_minikube()
        self.set_docker_env()

        self.check_if_deployed()  # info only
        Logger.info("Re-building and Re-deploying on every run.")
        self.build_images()
        self.deploy_k8s()

        self.wait_for_pods()
        self.show_access_urls()


if __name__ == "__main__":
    manager = InfrastructureManager()
    manager.main()
