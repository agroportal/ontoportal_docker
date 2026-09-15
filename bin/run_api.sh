#!/usr/bin/env bash
# Services of the API stack in docker-compose.yml (nginx fronts the API on
# the historical 9393 port; unicorn itself is no longer published)
API_SERVICES="api ncbo_cron redis solr mgrep virtuoso nginx"
# Same stack, but built from source (config/fairness/) instead of pulled: kept
# apart because 'docker compose pull' errors on a service with no published
# image
API_BUILD_SERVICES="fairness"

setup() {
  echo "[+] Setup API"
  if [ ! -f ".env" ]; then
    cp .env.sample .env
  fi
  source .env
}

status_ok() {
  curl -sSf http://$1:${NGINX_API_PORT:-9393} >/dev/null 2>&1
}

logs() {
  docker exec -it api-service tail -f log/production.log
}

reset_data() {
  echo "[+] Removing containers and data volumes"
  docker compose down --volumes --remove-orphans
  # Leftovers from the old layout where containers were started with 'docker compose run'
  docker container rm -f api-service ui-service cron-service >/dev/null 2>&1
}

clean() {
  echo "[+] Cleaning the API"
  reset_data
}

update() {
  echo "[+] Pulling latest images for the API"
  docker compose pull $API_SERVICES
  # cached after the first run; FAIRNESS_REF is what invalidates it (use
  # 'docker compose build --no-cache fairness' to rebuild a moving ref)
  echo "[+] Building the FAIRness assessment service"
  docker compose build $API_BUILD_SERVICES
}

stop() {
  echo "[+] Stopping the API"
  docker compose stop $API_SERVICES $API_BUILD_SERVICES
}

provision() {
  if [ -z "$1" ]; then
    source .env
    reset_data
    echo "[+] Running Cron provisioning"
    commands=(
        "bin/run_cron.sh 'bundle exec rake user:create[admin,admin@nodomain.org,password]'"
        "bin/run_cron.sh 'bundle exec rake user:adminify[admin]'"
        "bin/run_cron.sh 'bundle exec bin/ncbo_ontology_import --admin-user admin --ontologies $STARTER_ONTOLOGY --from-apikey $OP_APIKEY --from $OP_API_URL'"
        "bin/run_cron.sh 'bundle exec bin/ncbo_ontology_process -o ${STARTER_ONTOLOGY}'"
        # annotator term cache (redis) + mgrep dictionary and its lemmatized
        # variant (-d) on the shared volume. The lemmatizer these need is put in
        # place by the ncbo_cron entrypoint (config/ncbo_cron/entrypoint.sh),
        # which is why the step above can already lemmatize too.
        "bin/run_cron.sh 'bundle exec bin/ncbo_ontology_annotate_generate_cache -o ${STARTER_ONTOLOGY} -d'"
        # mgrep only loads the dictionary at startup
        "docker compose restart mgrep"
    )
    for cmd in "${commands[@]}"; do
        echo "[+] Run: $cmd"
        if ! eval "$cmd"; then
            echo "Error: Failed to run provisioning .  $cmd"
            exit 1
        fi
    done
    echo "CRON Setup completed successfully!"
  elif [ "$1" == "--no-provision" ]; then
    echo "[+] Skipping Cron provisioning"
  fi
}

# The FAIR scores are served from a cache file that the web service only reads:
# it is built by a separate command, which needs the API up and the ontologies
# already processed, hence a provisioning step of its own after run().
provision_fairness() {
  if [ "$1" == "--no-provision" ]; then
    echo "[+] Skipping the FAIR score cache generation"
    return 0
  fi

  source .env

  if [ "${FAIRNESS_CACHE_ENABLED:-true}" != "true" ]; then
    echo "[+] FAIR score cache disabled, scores are computed on request"
    return 0
  fi

  echo "[+] Generating the FAIR score cache (assesses every ontology of the portal)"
  if ! docker compose run --rm fairness fairness-cache; then
    # not fatal: the appliance is up, only the FAIR scores are missing
    echo "[-] Failed to generate the FAIR score cache. The FAIR scores will be"
    echo "    empty until 'docker compose run --rm fairness fairness-cache' succeeds."
  fi
}

run() {
  echo "[+] Starting the API"
  if ! docker compose up -d api nginx fairness; then
    echo "[-] Error starting the API containers. Exiting..."
    exit 1
  fi

  local HOST_IP='localhost'
  if [ -f "/.dockerenv" ]; then
    # we are inside the container of ontoportal_docker so we have to test the IP of the machine
    docker_host_IP=$(dig +short A host.docker.internal)
    if [ -n "$docker_host_IP" ]; then
      echo "IP of the local machine: $docker_host_IP"
      HOST_IP=$docker_host_IP
    else
      echo "Cannot get the IP address of the host machine, localhost will be used"
    fi
  fi
  local api_port="${NGINX_API_PORT:-9393}"
  source utils/loading_animation.sh "[+] Waiting for the server http://$HOST_IP:$api_port to be up..." "http://$HOST_IP:$api_port" 300

  if status_ok $HOST_IP; then
    echo "[+] API is up and running!"
  else
    echo "[x] Timed out waiting for the server to be up."
    exit 1
  fi
}

start() {
  echo "[+] Running api script"
  setup
  update
  provision "$1"
  run
  if [ $? -ne 0 ]; then
    echo "[-] Error Running API. Exiting..."
    exit 1
  fi
  provision_fairness "$1"
}

usage() {
  echo "Usage: $0 <option>"
  echo "Options:"
  echo "  start      Start the API"
  echo "  stop       Stop the API"
  echo "  logs       View the logs of the API"
  echo "  clean      Stop the appliance and remove all containers and data volumes"
  echo "  update     Update the API containers to the latest version"
  exit 1
}

# Option parser
if [[ $# -eq 0 ]]; then
  usage
fi


case $1 in
  "start")
    start "$2"
    ;;
  "stop")
    stop
    ;;
  "logs")
    logs
    ;;
  "clean")
    clean
    ;;
  "update")
    update
    ;;
  "setup")
    setup
    ;;
  *)
    echo "Invalid option: $1"
    usage
    ;;
esac

exit 0
