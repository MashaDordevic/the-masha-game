#!/usr/bin/env bash

set -euo pipefail

readonly local_java_home="$HOME/.local/share/jdks/temurin-21/Contents/Home"

if ! java -version >/dev/null 2>&1; then
  if [[ ! -x "$local_java_home/bin/java" ]]; then
    echo "Java 21 is required. Install Temurin 21 or set JAVA_HOME." >&2
    exit 1
  fi

  export JAVA_HOME="$local_java_home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

npm run test:functions
npm run build
npx firebase emulators:exec \
  --only auth,database,functions,hosting \
  --project themashagame-990a8 \
  "npx playwright test"
