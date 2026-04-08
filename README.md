# Docker Container Proxy by Traefik

A dynamic reverse proxy setup that automatically routes traffic to Docker containers based on their name and port using Traefik and a Ruby-based configuration generator.

## Features

- **Zero-config Routing**: Access any container via `http://<container-name>-<port>.localhost/`.
- **Automatic Detection**: Automatically detects new containers and their exposed ports.
- **Traefik Dashboard**: Built-in dashboard available at `http://localhost/`.
- **Lightweight**: Powered by Traefik v3.6 and Ruby 4.0 (Alpine).

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
2. **Generator**: A Ruby script that watches Docker events and updates routing rules.
3. **some-nginx**: A sample container for testing.

### Usage

Once started, you can access your containers using the following URL pattern:
`http://<container-name>-<port>.localhost/`

For the included sample:
- Access Nginx on port 80: [http://some-nginx-80.localhost/](http://some-nginx-80.localhost/)
- Access Nginx on port 8080: [http://some-nginx-8080.localhost/](http://some-nginx-8080.localhost/)

To see the Traefik Dashboard:
- [http://localhost/](http://localhost/)

## Configuration

### Customizing the Proxy Port

By default, Traefik binds to port `80`. You can change this using an environment variable:

```bash
DOCKER_CONTAINER_PROXY_BY_TRAEFIK_PORT=8000 docker compose up -d
```
Then access it via `http://localhost:8000/`.

### Adding Your Own Containers

To make your container accessible through the proxy, ensure:

1. It is attached to the `traefik-net` network.
2. It has one or more ports defined in `expose` (or `ports`).

Example `docker-compose.yml` for your app:

```yaml
services:
  my-app:
    image: my-app-image
    container_name: my-app
    expose:
      - "3000"
    networks:
      - traefik-net

networks:
  traefik-net:
    external: true
```

After starting your app, it will be automatically available at `http://my-app-3000.localhost/`.

## Architecture

- **Generator (Ruby 4.0)**: Watches `/var/run/docker.sock` and writes Traefik dynamic configuration to `config/dynamic_conf.yml`.
- **Traefik (v3.6)**: Watches the `config/` directory and applies routing rules in real-time.
