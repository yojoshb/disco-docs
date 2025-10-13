### Docker development container

Used for live docs rendering. Contains scripts for building, starting, and stopping the dev container. Sub-out `docker` commands for `podman` if using

#### Usage
Clone the repository and navigate to it

```bash
# Build container based on Dockerfile, the image will be named localhost/mkdocs-site
./_dev/build.sh

# Start container on port 8001, the container will be named mkdocs: http://localhost:8001
./_dev/start.sh

# Stop the mkdocs container
./_dev/stop.sh
```