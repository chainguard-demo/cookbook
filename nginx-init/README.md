# Minimal NGINX with Init Container Using Chainguard

## Problem Statement

By default, the upstream NGINX image runs `startup.sh` scripts inside the `/docker-entrypoint.d/` directory. While this is flexible, it introduces several **security risks**:

### ⚠️ Risks:
- **Arbitrary Code Execution**: Any `.sh` script placed in `/docker-entrypoint.d` (via CI/CD, build layers, or volume mounts) will be executed at container startup.
- **Unintended Script Execution**: Even accidental or malicious scripts will run.
- **Privilege Escalation**: If the container runs as root, these scripts have full system access.

---

## Solution: Use an Init Container

To mitigate this, we can **decouple NGINX’s startup logic** from the main container by using an **init container** to configure NGINX. The init container handles config setup via the default NGINX `docker-entrypoint.sh` logic and mounts config files into a shared volume.

---

## Dockerfile for the Init Container

This uses the official `nginx:1.25` image, copies in a custom `nginx.conf` and `mime.types`, and prepares the `/etc/nginx/` config path during init:

```Dockerfile
FROM nginx:1.25

# Copy your custom configuration
COPY nginx.conf /custom/nginx.conf
COPY mime.types /custom/mime.types

# Copy configs into the shared volume and invoke entrypoint logic
CMD cp /custom/nginx.conf /etc/nginx/nginx.conf && \
    cp /custom/mime.types /etc/nginx/mime.types && \
    chmod 644 /etc/nginx/* && \
    /docker-entrypoint.sh true
```

Once built and pushed, this image can be used in your Kubernetes workloads.

---

## Kubernetes Deployment

### Init Container

This runs once to copy NGINX configuration files and simulate the NGINX setup process:

```yaml
initContainers:
  - name: run-entrypoint
    image: bannimal/chainguard-init-nginx:latest
    volumeMounts:
      - name: nginx-config
        mountPath: /etc/nginx
```

### Main Container (Chainguard NGINX)

The Chainguard container picks up configuration from the shared volume:

```yaml
containers:
  - name: nginx
    image: cgr.dev/chainguard/nginx:latest
    ports:
      - containerPort: 80
    volumeMounts:
      - name: nginx-config
        mountPath: /etc/nginx
```

### Full Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-chainguard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-chainguard
  template:
    metadata:
      labels:
        app: nginx-chainguard
    spec:
      volumes:
        - name: nginx-config
          emptyDir: {}

      initContainers:
        - name: run-entrypoint
          image: bannimal/chainguard-init-nginx:latest
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx

      containers:
        - name: nginx
          image: cgr.dev/chainguard/nginx:latest
          ports:
            - containerPort: 80
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx
```

---

## Testing a Minimal NGINX Configuration

Minimal `nginx.conf` for testing:

```
nginx
worker_processes  1;
pid /tmp/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen 80;
        server_name localhost;

        location / {
            return 200 "Hello from minimal NGINX!\n";
            add_header Content-Type text/plain;
        }
    }
}
```

---

## Run & Test

Apply your deployment:

```bash
kubectl apply -f nginx-deployment-cg.yaml
kubectl get pods -w
```

Expected output:

```
NAME                                READY   STATUS    RESTARTS   AGE
nginx-chainguard-xxxx               0/1     Init      0          4s
nginx-chainguard-xxxx               1/1     Running   0          10s
```

Forward a port and test:

```bash
kubectl port-forward deploy/nginx-chainguard 8080:80
curl http://localhost:8080
```

Expected result:

```
Hello from minimal NGINX!
```

---

## Additional Resources

- Chainguard Minimal NGINX: [chainguard.dev](https://www.chainguard.dev)
- GitHub Repository for This Example: *(add your link here)*
