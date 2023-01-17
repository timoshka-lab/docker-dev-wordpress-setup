#!/usr/bin/env bash

set -eu

function load_env() {
  if [ -f .env ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' .env | xargs)
  fi
}

function report_error() {
    printf "\033[0;31mERROR: %s\033[0m\n" "$1" >&2
}

function report_success_message() {
    printf "\033[0;32m%s\033[0m\n" "$1"
}

function validate_env() {
  required=(PHP_VERSION WP_SITE_URL WP_EMAIL MYSQL_VERSION MYSQL_USER MYSQL_PASSWORD MYSQL_ROOT_PASSWORD MYSQL_DATABASE NGINX_VERSION NGINX_SERVER_NAME)

  for var in "${required[@]}"; do
    if [ -z "${!var}" ]; then
      report_error "$var is required environment variable"
      return 1
    fi
  done

  if ! [[ $PHP_VERSION =~ ^([0-9]+)(\.[0-9]+){0,2}$ ]]; then
    report_error "PHP_VERSION is not set or is invalid. Valid formats: '8', '8.0', '8.0.0'"
    return 1
  fi

  if ! [[ $WP_SITE_URL =~ ^https?://[-[:alnum:]:@/_.]*$ ]]; then
    report_error "WP_SITE_URL is not set or is invalid. Valid formats: 'http://example.test', 'https://example.test'"
    return 1
  fi

  if ! [[ $WP_EMAIL =~ ^[-_.+[:alnum:]]+@[-_.+[:alnum:]]+\.[[:alpha:]]+$ ]]; then
    report_error "WP_EMAIL is not set or is invalid. Valid formats: 'wp@example.test'"
    return 1
  fi

  if ! [[ $MYSQL_VERSION =~ ^([0-9]+)(\.[0-9]+){0,2}$ ]]; then
    report_error "MYSQL_VERSION is not set or is invalid. Valid formats: '8', '8.0', '8.0.0'"
    return 1
  fi

  if ! [[ $NGINX_VERSION =~ ^([0-9]+)(\.[0-9]+){0,2}$ ]]; then
    report_error "NGINX_VERSION is not set or is invalid. Valid formats: '1', '1.0', '1.0.0'"
    return 1
  fi

  if ! [[ $NGINX_SERVER_NAME =~ ^[-[:alnum:]/_.]*$ ]]; then
    report_error "NGINX_SERVER_NAME is not set or is invalid. Valid formats: 'example.test'"
    return 1
  fi

  return 0
}

function validate_env_input() {
  read -p "Edit the '.env' file, and press enter key to continue:"
  load_env

  if ! validate_env; then
    validate_env_input
    load_env
  fi
}

function validate_working_dir() {
  if [ "$(ls -A | wc -l)" -gt 1 ]; then
     echo "Error: working directory is not empty." >&2
     exit 1
  fi
}

function validate_dependencies() {
  if [ ! -x "$(command -v docker)" ]; then
    echo "Error: docker is not installed." >&2
    exit 1
  fi

  if [ ! -x "$(command -v curl)" ]; then
    echo "Error: curl is not installed." >&2
    exit 1
  fi
}

function generate_rand_hash() {
  LC_ALL=C tr -dc 'A-Za-z0-9!%#&()-+*.=<>@^_~' </dev/urandom | head -c 64 ; echo ''
}

function generate_wp_salt_env() {
  if [ -e "/dev/urandom" ]; then
    echo "Generating random salts..."
    {
      echo "WP_AUTH_KEY=\"$(generate_rand_hash)\""
      echo "WP_SECURE_AUTH_KEY=\"$(generate_rand_hash)\""
      echo "WP_LOGGED_IN_KEY=\"$(generate_rand_hash)\""
      echo "WP_NONCE_KEY=\"$(generate_rand_hash)\""
      echo "WP_AUTH_SALT=\"$(generate_rand_hash)\""
      echo "WP_SECURE_AUTH_SALT=\"$(generate_rand_hash)\""
      echo "WP_LOGGED_IN_SALT=\"$(generate_rand_hash)\""
      echo "WP_NONCE_SALT=\"$(generate_rand_hash)\""
    } > .env.wp-salt
  else
    echo "Skipping generating WP salts, /dev/urandom is not available."
  fi
}

function init_project() {
  curl -L https://github.com/timoshka-lab/docker-dev-wordpress/archive/main.tar.gz | tar xvz -C ./ --strip-components=1
  cp .env.example .env
  generate_wp_salt_env
}

function provision_docker_environment() {
  docker compose build
  docker compose up -d
  docker compose exec app /setup.sh
}

function main() {
  validate_working_dir
  validate_dependencies

  echo "Starting auto setup..."

  init_project
  validate_env_input
  provision_docker_environment

  if [ "$NGINX_ENABLE_SSL" = true ]; then
    if [ -x "$(command -v security)" ]; then
      echo "Installing ssl certificate into keychain..."
      sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$(pwd)/docker/nginx/certs/server.crt"
    else
      echo "Warning: you have to add ssl certificate to your keychain manually."
    fi
  fi

  report_success_message "Auto setup is now Done!"
}

main