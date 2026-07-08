#!/usr/bin/env bash
# Services of the UI stack in docker-compose.yml (nginx serves the UI on
# port 80; puma itself is no longer published)
UI_SERVICES="ui db cache nginx"

setup() {
  echo "[+] Setup UI"
  if [ ! -f ".env" ]; then
    cp .env.sample .env
  fi
  source .env
}

status_ok() {
  curl -sSf http://$1:${NGINX_HTTP_PORT:-80} >/dev/null 2>&1
}

logs() {
  docker logs ui-service -f
}

update() {
  echo "[+] Pulling latest images for the UI"
  docker compose pull $UI_SERVICES
}

clean() {
  echo "[+] Cleaning the UI"
  docker compose down --volumes --remove-orphans
  # Leftovers from the old layout where containers were started with 'docker compose run'
  docker container rm -f api-service ui-service cron-service >/dev/null 2>&1
}

stop() {
  echo "[+] Stopping the UI"
  docker compose stop $UI_SERVICES
}

run() {
  source .env

  if [ -z "$API_URL" ] || [ -z "$API_KEY" ]; then
    echo "[-] Error: Missing required arguments. Please provide both API_URL and API_KEY in your .env"
    exit 1
  fi

  echo "[+] Starting the UI"
  if ! docker compose up -d ui nginx; then
    echo "[x] UI containers failed to start"
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
  local ui_port="${NGINX_HTTP_PORT:-80}"
  source utils/loading_animation.sh "[+] Waiting for the server http://$HOST_IP:$ui_port to be up..." "http://$HOST_IP:$ui_port" 300

  if status_ok $HOST_IP; then
    echo "[+] UI is up and running!"
  else
    echo "[x] Timed out waiting for the UI to be up."
    exit 1
  fi
}

start() {
  echo "[+] Running ui script"
  setup
  update
  run
  if [ $? -ne 0 ]; then
    echo "[-] Error Running UI. Exiting..."
    exit 1
  fi
}

usage() {
  echo "Usage: $0 <option>"
  echo "Options:"
  echo "  start      Start the UI"
  echo "  stop       Stop the UI"
  echo "  logs       View the logs of the UI"
  echo "  clean      Stop the appliance and remove all containers and data volumes"
  echo "  update     Update the UI containers to the latest version"
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
