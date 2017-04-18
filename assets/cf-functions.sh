
function cf_login() {
  local api_endpoint=$1
  local cf_user=$2
  local cf_pass=$3
  local skip_ssl_validation=$4

  local cf_skip_ssl_validation=""
  if [ "$skip_ssl_validation" = "true" ]; then
    cf_skip_ssl_validation="--skip-ssl-validation"
  fi

  cf api "$api_endpoint" "$cf_skip_ssl_validation"

  cf auth "$cf_user" "$cf_pass"
}

function cf_target() {
  local org=$1
  local space=$2
  if [ -n "$space" ]; then
    cf target -o "$org" -s "$space"
  else
    cf target -o "$org"
  fi
}

function cf_get_org_guid() {
  local org=$1
  cf curl "/v2/organizations" -X GET -H "Content-Type: application/x-www-form-urlencoded" -d "q=name:$org" | jq -r '.resources[].metadata.guid'
}

function cf_org_exists() {
  local org=$1
  [ -n "$(cf_get_org_guid $org)" ]
}

function cf_create_org() {
  local org=$1
  cf create-org "$org"
}

function cf_create_org_if_not_exists() {
  local org=$1
  if ! (cf_org_exists "$org"); then
    cf_create_org "$org"
  fi
}

function cf_delete_org() {
  cf delete-org "$1" -f
}

function cf_get_space_guid() {
  local org=$1
  local space=$2
  local org_guid=$(cf_get_org_guid "$org")
  cf curl "/v2/spaces" -X GET -H "Content-Type: application/x-www-form-urlencoded" -d "q=name:$space;organization_guid:$org_guid" | jq -r '.resources[].metadata.guid'
}

function cf_space_exists() {
  local org=$1
  local space=$2
  [ -n "$(cf_get_space_guid $org $space)" ]
}

function cf_create_space() {
  local org=$1
  local space=$2
  cf create-space "$space" -o "$org"
}

function cf_create_space_if_not_exists() {
  local org=$1
  local space=$2
  if ! (cf_space_exists "$org" "$space"); then
    cf_create_space "$org" "$space"
  fi
}

function cf_delete_space() {
  local org=$1
  local space=$2
  cf delete-space "$space" -o "$org" -f
}

function cf_service_exists() {
  local service_instance=$1
  cf curl /v2/service_instances | jq -e --arg name "$service_instance" '.resources[] | select(.entity.name == $name) | true' >/dev/null
}

function cf_create_service() {
  local service=$1
  local plan=$2
  local service_instance=$3
  local configuration=$4
  local tags=$5
  cf create-service "$service" "$plan" "$service_instance" -c "$configuration" -t "$tags"
}

function cf_delete_service() {
  local service_instance=$1
  cf delete-service "$service_instance" -f
}

function cf_wait_for_service_instance() {
  local service_instance=$1
  local timeout=${2:-600}

  local guid=$(cf service "$service_instance" --guid)
  local start=$(date +%s)

  echo "Waiting for service: $service_instance"
  while true; do
    # Get the service instance info in JSON from CC and parse out the async 'state'
    local state=$(cf curl "/v2/service_instances/$guid" | jq -r .entity.last_operation.state)

    if [ "$state" = "succeeded" ]; then
      echo "Service $service_instance is ready"
      return
    elif [ "$state" = "failed" ]; then
      echo "Service $service_instance failed to provision:"
      cf curl "/v2/service_instances/$guid" | jq -r .entity.last_operation.description
      exit 1
    fi

    local now=$(date +%s)
    local time=$(($now - $start))
    if [[ "$time" -ge "$timeout" ]]; then
      echo "Timed out waiting for service instance to provision: $service_instance"
      exit 1
    fi
    sleep 5
  done
}

function cf_bind_service() {
  local app_name=$1
  local service_instance=$2
  local configuration=$3
  cf bind-service "$app_name" "$service_instance" -c "$configuration"
}

function cf_is_app_bound_to_service() {
  local app_name=$1
  local service_instance=$2
  local app_guid=$(cf app "$app_name" --guid)
  local si_guid=$(cf service "$service_instance" --guid)
  cf curl "/v2/apps/$app_guid/service_bindings" -X GET -H "Content-Type: application/x-www-form-urlencoded" -d "q=service_instance_guid:$si_guid" | jq -e '.total_results == 1' >/dev/null
}

function cf_push() {
  local args=$1
  cf push $args
}

function cf_zero_downtime_push() {
  local args=$1
  local current_app_name=$2
  if [ -n "$current_app_name" ]; then
    cf zero-downtime-push "$current_app_name" $args
  else
    cf push $args
  fi
}

function cf_start() {
  local app_name=$1
  local staging_timeout=$2
  local startup_timeout=$3
  if [ "$staging_timeout" -gt "0" ]; then
    export CF_STAGING_TIMEOUT=$staging_timeout
  fi
  if [ "$startup_timeout" -gt "0" ]; then
    export CF_STARTUP_TIMEOUT=$startup_timeout
  fi

  cf start "$app_name"

  unset CF_STAGING_TIMEOUT
  unset CF_STARTUP_TIMEOUT
}

function cf_delete() {
  local app_name=$1
  local delete_mapped_routes=$2
  if [ -n "$delete_mapped_routes" ]; then
    cf delete "$app_name" -f -r
  else
    cf delete "$app_name" -f
  fi
}