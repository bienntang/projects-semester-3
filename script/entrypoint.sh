#!/usr/bin/env bash

# User-provided configuration must always be respected.
# This script derives Airflow AIRFLOW__ variables only when the user has not provided their own configuration.

TRY_LOOP="20"

# Global defaults and backward compatibility
: "${AIRFLOW_HOME:="/usr/local/airflow"}"
: "${AIRFLOW_CORE_FERNET_KEY:=${FERNET_KEY:=$(python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')}}"
: "${AIRFLOW_CORE_EXECUTOR:=${EXECUTOR:-Sequential}Executor}"

# Load DAGs examples (default: Yes)
if [[ -z "$AIRFLOW_CORE_LOAD_EXAMPLES" && "${LOAD_EX:=n}" == "n" ]]; then
  AIRFLOW_CORE_LOAD_EXAMPLES=False
fi

# Export environment variables
export \
  AIRFLOW_HOME \
  AIRFLOW_CORE_EXECUTOR \
  AIRFLOW_CORE_FERNET_KEY \
  AIRFLOW_CORE_LOAD_EXAMPLES

# Install custom Python packages if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    pip install --user -r /requirements.txt
fi

# Function to wait for a specific port to become available
wait_for_port() {
  local name="$1"
  local host="$2"
  local port="$3"
  local attempts=0
  
  while ! nc -z "$host" "$port" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$TRY_LOOP" ]; then
      echo >&2 "$(date) - $host:$port is still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $attempts/$TRY_LOOP"
    sleep 5
  done
}

# Check if an SQL database is needed based on the executor type
if [ "$AIRFLOW_CORE_EXECUTOR" != "SequentialExecutor" ]; then
  # Check if the user has provided a database connection string
  if [ -z "$AIRFLOW_CORE_SQL_ALCHEMY_CONN" ]; then
    # Default values for PostgreSQL connection
    : "${POSTGRES_HOST:="postgres"}"
    : "${POSTGRES_PORT:="5432"}"
    : "${POSTGRES_USER:="airflow"}"
    : "${POSTGRES_PASSWORD:="airflow"}"
    : "${POSTGRES_DB:="airflow"}"
    : "${POSTGRES_EXTRAS:-""}"

    AIRFLOW_CORE_SQL_ALCHEMY_CONN="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}${POSTGRES_EXTRAS}"
    export AIRFLOW_CORE_SQL_ALCHEMY_CONN

    # For CeleryExecutor, set the result backend
    if [ "$AIRFLOW_CORE_EXECUTOR" = "CeleryExecutor" ]; then
      AIRFLOW_CELERY_RESULT_BACKEND="db+postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}${POSTGRES_EXTRAS}"
      export AIRFLOW_CELERY_RESULT_BACKEND
    fi
  else
    # Ensure AIRFLOW_CELERY_RESULT_BACKEND is set if using CeleryExecutor
    if [[ "$AIRFLOW_CORE_EXECUTOR" == "CeleryExecutor" && -z "$AIRFLOW_CELERY_RESULT_BACKEND" ]]; then
      >&2 echo "FATAL: If you set AIRFLOW_CORE_SQL_ALCHEMY_CONN manually with CeleryExecutor, you must also set AIRFLOW_CELERY_RESULT_BACKEND."
      exit 1
    fi

    # Extract useful variables from the provided connection string
    POSTGRES_ENDPOINT=$(echo -n "$AIRFLOW_CORE_SQL_ALCHEMY_CONN" | cut -d '/' -f3 | sed -e 's,.*@,,')
    POSTGRES_HOST=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f1)
    POSTGRES_PORT=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f2)
  fi

  wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
fi

# Configure Redis for CeleryExecutor
if [ "$AIRFLOW_CORE_EXECUTOR" = "CeleryExecutor" ]; then
  # Check if the user has provided a broker URL
  if [ -z "$AIRFLOW_CELERY_BROKER_URL" ]; then
    # Default values for Redis connection
    : "${REDIS_PROTO:="redis://"}"
    : "${REDIS_HOST:="redis"}"
    : "${REDIS_PORT:="6379"}"
    : "${REDIS_PASSWORD:=""}"
    : "${REDIS_DBNUM:="1"}"

    # Construct the Redis broker URL
    REDIS_PREFIX=""
    if [ -n "$REDIS_PASSWORD" ]; then
      REDIS_PREFIX=":${REDIS_PASSWORD}@"
    fi

    AIRFLOW_CELERY_BROKER_URL="${REDIS_PROTO}${REDIS_PREFIX}${REDIS_HOST}:${REDIS_PORT}/${REDIS_DBNUM}"
    export AIRFLOW_CELERY_BROKER_URL
  else
    # Extract useful variables from the provided broker URL
    REDIS_ENDPOINT=$(echo -n "$AIRFLOW_CELERY_BROKER_URL" | cut -d '/' -f3 | sed -e 's,.*@,,')
    REDIS_HOST=$(echo -n "$REDIS_ENDPOINT" | cut -d ':' -f1)
    REDIS_PORT=$(echo -n "$REDIS_ENDPOINT" | cut -d ':' -f2)
  fi

  wait_for_port "Redis" "$REDIS_HOST" "$REDIS_PORT"
fi

# Main command execution
case "$1" in
  webserver)
    airflow db init
    if [ "$AIRFLOW_CORE_EXECUTOR" = "LocalExecutor" ] || [ "$AIRFLOW_CORE_EXECUTOR" = "SequentialExecutor" ]; then
      # Start the scheduler in the background for Local/Sequential executors
      airflow scheduler &
    fi
    exec airflow webserver
    ;;
  worker|scheduler)
    # Give the webserver time to initialize the database
    sleep 10
    exec airflow "$@"
    ;;
  flower)
    sleep 10
    exec airflow "$@"
    ;;
  version)
    exec airflow "$@"
    ;;
  *)
    # For any other command, run it in the right environment
    exec "$@"
    ;;
esac
