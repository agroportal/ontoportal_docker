# OntoPortal docker
OntoPortal Docker is a comprehensive collection of scripts designed to facilitate the running, testing, and deployment of ontoPortal using Docker.

With this project, you can quickly spin up a fully functional ontoPortal instance with minimal setup by leveraging docker's containerization technology. This allows you to test its features and deploy the instance using Kamal.

## Features
- Start ontoportal instance (with or without parsing ontology)
- Start specific services (API/UI)
- Build docker image for this project and push it to your repository 
- Deploy the instance to server

## Project architecture
- **bin**: directory contains essential scripts for deploying and running various components of the ontoPortal system
- **config**: contains deploy.yml file which contains settings and parameters required for deployment using kamal deployment tool, `config/nginx/` with the reverse-proxy configuration and `config/fairness/` with the FAIRness assessment service (see below)
- **test**: testing-related files and scripts using bats testing framework
- **utils**: utility and additional scripts for various purposes
- **docker-compose.yml**: the appliance topology (API, UI and all their backing services). This file is owned by this repo; the api/ui repositories keep their own compose files for their development workflows
- **.env.sample**: sample file contains configuration of the ontoportal instance (will be copied to .env when running)
- **Dockerfile**: defines configurations to build the docker image for the project
- **ontoportal**: the main script to run the ontoportal, it includes the entry point and main execution logic for the ontoPortal services
- **run**: This file is used to set up environment for tests (it will be deleted).
## Prerequisites
- [git](https://git-scm.com/downloads)
- [Docker](https://docs.docker.com/engine/install/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Kamal deploy tool](https://kamal-deploy.org/docs/installation/) (if you plan to use the deploy feature)

## Installation
```
~> git clone https://github.com/ontoportal-lirmm/ontoportal_docker.git
~> cd ontoportal-docker
```
## Usage
### General Command Structure
```
./ontoportal <command> [arguments]
```
### Commands
- **Start**
    - start ontoportal instance
    ```
    ./ontoportal start [--no-provision]
    ```
    - start specific services (API or UI)
    ```
    ./ontoportal start [api|ui] [--no-provision]
    ```
    - `--no-provision`: Start the appliance without any data (an empty appliance).

- **Deploy**
    - build and push image to repository (by default docker hub)
    ```
    ./ontoportal deploy push
    ```
    - Deploy ontoportal instance to server (or just specific services mentioned in the arguments)
    ```
    ./ontoportal deploy [api|ui]
    ```
- **Stop**: stop the OntoPortal API and UI services.
    ```
    ./ontoportal stop [api|ui]
    ```
- **Clean**: clean up the server. This removes all data, Docker Compose files, and containers
    ```
    ./ontoportal clean [-f]
    ```
    - `-f` : for force clean

- **Help**: display the help message.
    ```
    ./ontoportal help
    ```

### Reverse proxy (nginx)
An nginx container is the single public entry point of the appliance; the application servers (puma for the UI, unicorn for the API) are only reachable through it and no longer publish ports themselves:
- UI: `http://localhost` (host port `NGINX_HTTP_PORT`, default 80)
- API: `http://localhost:9393` (host port `NGINX_API_PORT`, kept on the API's historical port so existing `API_URL` values and clients keep working)

nginx provides slow-client buffering (required by unicorn), gzip compression, upload size limits (`NGINX_MAX_BODY_SIZE`) and upstream timeouts (`NGINX_PROXY_READ_TIMEOUT`). Its configuration lives in `config/nginx/templates/default.conf.template`; the `${NGINX_*}` placeholders are filled from `.env` at container startup. To serve HTTPS, follow the instructions in `config/nginx/ssl.conf.example`.

### FAIRness assessment (O'FAIRe)

[O'FAIRe](https://github.com/agroportal/fairness) scores the ontologies of the appliance against the FAIR principles; the UI shows the result on the ontology pages and on the landscape page. It is a Java web service, so unlike the other services it is *built* rather than pulled: `config/fairness/Dockerfile` compiles the war from source (`FAIRNESS_REF` pins the ref) and deploys it on Tomcat. nginx publishes it next to the API:

```
http://localhost:9393/ofaire?ontologies=STY
http://localhost:9393/ofaire?ontologies=STY,AGRO&combined   # + the group scores
http://localhost:9393/ofaire?ontologies=STY&sync            # ignore the cache
```

The service does not compute a score per request: with `FAIRNESS_CACHE_ENABLED=true` it answers from a cache file that a separate command builds by assessing every ontology of the portal. `./ontoportal start` builds it once at the end of provisioning; **an ontology added afterwards has no FAIR score until the cache is rebuilt**:

```
docker compose run --rm fairness fairness-cache
```

Schedule that command (a nightly cron on the host is what AgroPortal does) to keep the scores current. Setting `FAIRNESS_CACHE_ENABLED=false` assesses on every request instead — always fresh, but the UI gives up after 30 s, which a whole-portal request will exceed as soon as the portal grows.

The remaining knobs are in `.env`: `FAIRNESS_DISABLED` (hides the feature in the UI), `FAIRNESS_URL` (where the UI reads the scores — set it to the *public* URL in a public deployment), `FAIRNESS_PORTAL`, `FAIRNESS_API_URL`, `FAIRNESS_ADMIN_APIKEY` (an admin apikey also assesses the private ontologies) and `FAIRNESS_JAVA_OPTS`.

### Additional Notes
- You can provide your own `.env` file to customize parameters. Place the .env file in the project directory.
- The service topology (containers, hostnames, volumes) lives in `docker-compose.yml` in this repository; edit that file directly to change it.
- `.env` file contains 5 parts:
    - **General configuration**: where you can specify:
    ```yml
    IMAGE_REPOSITORY: Docker Hub organization of the OntoPortal images (api, cron, ui)
    IMAGE_TAG: tag of the OntoPortal images to run
    SERVICE: specify the service you want to run (script will handle this)
    ```
    - **API Configurations:** contains settings for api service
    - **UI Configurations:** contains settings for ui service
    - **NGINX Configurations:** published ports and proxy limits of the reverse proxy
    - **Cron Configurations:** contains settings for cron service
    - **Kamal configurations**: for build and deployment of the ontoportal instance:
    ```yml
    IMAGE_NAME: the name of the image to build and push to docker hub
    SERVER_IP: the ip server where you want to deploy the instance 
    DOCKER_REGISTRY_NAME: the name of account in docker hub of another repository
    KAMAL_REGISTRY_PASSWORD: password of token to access the repository
    SSH_USER: the user that will be used when deploying into the server
    ```

### Upgrading from an older checkout
Older versions downloaded the compose files from the api/ui repositories at start time; the topology is now versioned here in `docker-compose.yml`. If you upgraded an existing checkout:
- Delete your `.env` (or update it: remove `ORGANIZATION_NAME`/`COMPOSE_*_FILE_PATH` and set `IMAGE_REPOSITORY=agroportal`, `IMAGE_TAG=development`), then run `./ontoportal clean -f` once to remove containers and files from the old layout.
- The UI moved from `http://localhost:3000` to `http://localhost` (port 80): everything is now served through the nginx reverse proxy. The API stays on port 9393, but served by nginx. Update `UI_URL` in an existing `.env` accordingly.