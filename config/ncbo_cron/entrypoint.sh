#!/usr/bin/env bash
# Make the lemmatizer reachable, then run the command.
#
# ncbo_annotator shells out to `java -jar <lemmatizer_jar>/Lemmatizer.jar` and
# defaults lemmatizer_jar to 'lib/Lemmatizer' (ncbo_annotator/config.rb),
# resolved against the working directory; the appliance images do not override
# that setting. The jar and the TreeTagger models it needs ship inside the gem
# itself -- it is a git checkout of agroportal/ncbo_annotator@development -- so
# link them where the gem expects to find them.
#
# This belongs to the entrypoint rather than to the service command because
# every annotator step runs in its own container: provisioning and
# bin/run_cron.sh invoke the cron commands with 'docker compose run', and
# ncbo_ontology_process lemmatizes the dictionary just like
# ncbo_ontology_annotate_generate_cache does. An entrypoint survives the command
# override of 'docker compose run'; a command does not.
#
# Without the link the dictionary and the annotator redis cache are still
# written, and only the lemmatized dictionary fails -- which is why the failure
# used to look like a successful provisioning.
set -euo pipefail

gem_path="$(bundle info ncbo_annotator --path 2>/dev/null || true)"

if [ -n "${gem_path}" ] && [ -f "${gem_path}/lib/Lemmatizer/Lemmatizer.jar" ]; then
  mkdir -p lib
  ln -sfn "${gem_path}/lib/Lemmatizer" lib/Lemmatizer
else
  echo "[!] Lemmatizer.jar not found in the ncbo_annotator gem (${gem_path:-gem not found})." >&2
  echo "[!] The lemmatized dictionary (dictionary-lem.txt) cannot be generated." >&2
fi

exec "$@"
