import csv
import subprocess
import json
import time
from datetime import datetime


NAMESPACE = "xz-check-namespace"


def get_clusters():
    clusters = (
        subprocess.check_output("kubectl config get-contexts -o name", shell=True)
        .decode()
        .split()
    )
    return clusters


def get_nodes(cluster):
    subprocess.check_call(f"kubectl config use-context {cluster}", shell=True)
    try:
        nodes = subprocess.check_output(
            "kubectl get nodes -o json", shell=True
        ).decode()
        nodes = json.loads(nodes)["items"]
        return [node["metadata"]["name"] for node in nodes]
    except subprocess.CalledProcessError:
        print(f"Failed to get nodes from cluster {cluster}")
        return []


def create_pod(node):
    pod_name = f"xz-check-{node}"
    pod_json = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {"name": pod_name, "labels": {"app": "xz-check"}},
        "spec": {
            "containers": [
                {
                    "name": "xz-check",
                    "image": "alpine",
                    "command": [
                        "nsenter",
                        "-t",
                        "1",
                        "-m",
                        "-u",
                        "-i",
                        "-n",
                        "-p",
                        "--",
                        "sh",
                        "-c",
                        "xz --version || echo 'Not installed' || true",
                    ],
                    "imagePullPolicy": "IfNotPresent",
                    "securityContext": {"privileged": True},
                }
            ],
            "restartPolicy": "Never",
            "nodeSelector": {"kubernetes.io/hostname": node},
            "hostPID": True,
            "tolerations": [
                {
                    "key": "sag",
                    "operator": "Equal",
                    "value": "webshopsv",
                    "effect": "NoSchedule",
                },
                {
                    "key": "sag",
                    "operator": "Equal",
                    "value": "webshopsvcon",
                    "effect": "NoSchedule",
                },
            ],
        },
    }

    try:
        p1 = subprocess.Popen(["echo", json.dumps(pod_json)], stdout=subprocess.PIPE)
        p2 = subprocess.Popen(
            ["kubectl", "apply", "-f", "-", "--namespace", NAMESPACE],
            stdin=p1.stdout,
            stdout=subprocess.PIPE,
        )
        p1.stdout.close() # type: ignore
        p2.communicate()
    except subprocess.CalledProcessError:
        print(f"Failed to create pod on node {node}")


def check_xz(node):
    pod_name = f"xz-check-{node}"
    try:
        version = (
            subprocess.check_output(
                f"kubectl logs {pod_name} --namespace {NAMESPACE}", shell=True
            )
            .decode()
            .split("\n")[0]
        )
        subprocess.check_call(
            f"kubectl delete pod {pod_name} --namespace {NAMESPACE}", shell=True
        )
    except subprocess.CalledProcessError:
        print(f"Failed to get logs from pod on node {node}")
        version = "Error"
    return version


def main():
    date_str = datetime.now().strftime("%d.%m.%Y")
    output_file = f"scan_k8s_for_xz_{date_str}.csv"
    with open(output_file, "w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["Cluster", "Node", "xz Version"])
        for cluster in get_clusters():
            subprocess.check_call(f"kubectl config use-context {cluster}", shell=True)
            try:
                subprocess.check_call(
                    f"kubectl create namespace {NAMESPACE}", shell=True
                )
            except subprocess.CalledProcessError:
                print(f"Namespace {NAMESPACE} already exists in cluster {cluster}")
            for node in get_nodes(cluster):
                create_pod(node)
        time.sleep(120)  # wait for 2 minutes
        for cluster in get_clusters():
            subprocess.check_call(f"kubectl config use-context {cluster}", shell=True)
            for node in get_nodes(cluster):
                version = check_xz(node)
                writer.writerow([cluster, node, version])


if __name__ == "__main__":
    main()
