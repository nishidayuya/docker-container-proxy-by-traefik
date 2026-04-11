# Docker Container Proxy by Traefik

A dynamic reverse proxy setup that automatically routes traffic to any Docker container on your host based on their name and port. Powered by Traefik and a Ruby-based configuration generator.

## Features

- **True Zero-Config Routing**: Access any container via `http://<container-name>-<port>.localhost/`. No `networks` or `labels` required in your containers!
- **Automatic Detection**: Automatically detects new containers and their exposed ports.
- **Dynamic Networking**: The proxy automatically connects itself to your target container's networks.
- **Traefik Dashboard**: Built-in dashboard available at `http://localhost/`.
- **Lightweight**: Powered by Traefik v3.6.13 and Ruby 4.0.2 (Alpine).

## Getting Started

### Prerequisites

- Docker and Docker Compose

### Launch the Proxy

Clone this repository and run:

```bash
docker compose up -d
```

This will start:
1. **Traefik**: The edge router (bound to `127.0.0.1:80`).
2. **Generator**: A Ruby script that watches Docker events and dynamically manages routing and networking.

### Usage

Once started, you can access your containers using the following URL pattern:
`http://<container-name>-<port>.localhost/`

> [!NOTE]
> If the container name contains underscores (`_`), they will be automatically replaced with hyphens (`-`).
> For example, a container named `my_web_app` will be accessible at `http://my-web-app-80.localhost/`.

For example, if you run a standalone nginx:
```bash
docker run --name my-nginx -d nginx:alpine
```
It will be automatically available at: [http://my-nginx-80.localhost/](http://my-nginx-80.localhost/)

To see the Traefik Dashboard:
- [http://localhost/](http://localhost/)

## Configuration

### Customizing the Proxy Port

By default, Traefik binds to port `80` on `127.0.0.1`. You can change this using an environment variable:

```bash
DOCKER_CONTAINER_PROXY_BY_TRAEFIK_PORT=8000 docker compose up -d
```
Then access it via `http://localhost:8000/`.

### How it Works

To make a container accessible through the proxy, it only needs to meet one condition:
- It must have one or more ports defined in `expose` (or `ports`).

The proxy will handle the rest:
1. The **Generator** detects the new container.
2. It instructs **Traefik** to connect to the target container's network.
3. It generates a routing rule for `http://<container-name>-<port>.localhost/`.

## Architecture

- **Generator (Ruby 4.0.2)**: Watches `/var/run/docker.sock`, manages Traefik's network connections, and writes dynamic configuration to `config/dynamic_conf.yml`.
- **Traefik (v3.6.13)**: Watches the `config/` directory and applies routing rules in real-time.
