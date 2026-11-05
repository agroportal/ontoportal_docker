# Here you write the tests
# And run them using test/run_tests.sh
setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/../src:$PATH"
}

@test "Running and Stopping API" {
   ./ontoportal clean -f

  run ./ontoportal start api
  assert_output --partial "[+] API is up and running!"

  # The starter ontology comes from the copy in data/ontologies/: a submission
  # pulled from a remote portal would carry its download URL (and apikey).
  source .env
  run curl -s "http://localhost:${NGINX_API_PORT:-9393}/ontologies/${STARTER_ONTOLOGY}/latest_submission?display=pullLocation"
  assert_output --partial '"pullLocation":null'

  ./ontoportal stop api
  run docker compose ps
  assert_output "NAME      IMAGE     COMMAND   SERVICE   CREATED   STATUS    PORTS"
}

@test "Running and Stopping UI" {
   ./ontoportal clean -f

  # this will start local api and the ui
  run ./ontoportal start

  assert_output --partial "[+] UI is up and running!"

  # FAIR scores of the starter ontology, requested the way the UI does it: the
  # portal parameter it derives from API_URL means nothing to O'FAIRe, and
  # nginx drops it so the service falls back to the portal the appliance
  # configures (see the /ofaire location). Also covers the cache, which
  # provisioning builds and which the service answers from.
  source .env
  run curl -s "http://localhost:${NGINX_API_PORT:-9393}/ofaire?portal=${API_URL}&ontologies=${STARTER_ONTOLOGY}&combined"
  assert_output --partial '"success":true'
  assert_output --partial '"normalizedScore"'

  ./ontoportal stop api
  ./ontoportal stop ui

  run docker compose ps
  assert_output "NAME      IMAGE     COMMAND   SERVICE   CREATED   STATUS    PORTS"
}
