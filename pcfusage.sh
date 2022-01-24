#!/usr/local/bin/bash
PREFIX=dev

#set -e

usage_and_exit() {
  cat <<EOF
Usage: pcfusage <PREFIX> <CMD>[ALL|APPS|SRVS|TACKLE] <STAGE>[dev]
  
  where: CMD=ALL    - all foundation information
         CMD=APPS   - Apps in CSV format - REQUIRED THE OUTPUT OF 'ALL' RUN
         CMD=SRVS   - service bindings - REQUIRED THE OUTPUT OF 'ALL' RUN
         CMD=TACKLE_APP - Apps in Tackle CSV format (https://www.konveyor.io/tackle) - REQUIRED THE OUTPUT OF 'ALL' RUN
         CMD=TACKLE_ORG - Apps in Tackle CSV format, one CF organisation is treated as one application (https://www.konveyor.io/tackle) - REQUIRED THE OUTPUT OF 'ALL' RUN

Examples:
  pcfusage dev - defaults to ALL
  pcfusage dev apps - creates apps csv file
  pcfusage dev srvs - creates a file with the app bindings guids
  pcfusage dev tackle - creates apps Tackle csv file, stage defaults to 'dev'
EOF
  exit 1
}

###############################################
# CREATE_ARRAY - Create an array of spaces in the system org we used to filter those apps
###############################################
create_array() {

local TRACE_OFF=${1:-FALSE}

  system_org_guid=`jq ".[].orgs[]? | select(.name == \"$1\") | .org_guid" ${PREFIX}_foundation.json`
  if [ -z "$system_org_guid" ]; then
    if [ "$TRACE_OFF" == "FALSE" ]; then
      printf "\nOrg $1 not found. Skipping...\n"
    fi
    return
  fi

  if [ "$#" -gt 1 ]; then
    arr=$arr","
  fi

  if [ "$TRACE_OFF" == "FALSE" ]; then
    printf "\n$1 Org GUID is $system_org_guid \n"
  fi

  spaces=$(cat ${PREFIX}_foundation.json | jq ".[].spaces[]? | select(.org == $system_org_guid) | .space_guid")
  if [ "$TRACE_OFF" == "FALSE" ]; then
    printf "\nSpaces in $1 org are: \n'$spaces' \n"
  fi

  c=1
  while read -r line; do
      #echo "... $line ..."
      if [ "$c" -gt "1" ]; then
         arr=$arr","
      fi
      arr=${arr}${line}
      c=$((c + 1))
  done <<< "$spaces"

}

################################################
# Creates CSV file with non system applications
################################################
create_csv() {
printf "\nNow I'm generating CSV file with only non system apps...\n"

non_system_app

jq -r ".apps[] | [.name, .memory, .state, .instances, .buildpack, .space, .updated] | @csv" --compact-output ${PREFIX}_final_apps.json > ${PREFIX}_apps.csv
rm ${PREFIX}_final_apps.json

printf "\nCreated '${PREFIX}_apps.csv'!"
}

################################################
# NON_SYSTEM_APPS - Creates a list of non-system apps
################################################
non_system_app() {

if [ ! -f "${PREFIX}_foundation.json" ]; then
    printf "\nERROR: Foundation file '${PREFIX}_foundation.json' doesn't exist.\n"
    printf "Make sure you ran with CMD=ALL (default), first"
    exit 1
fi

local TRACE_OFF=${1:-FALSE}

if [ "$TRACE_OFF" == "FALSE" ]; then
  printf "\ncreating ${PREFIX}_final_apps.json file...\n"
fi

arr="["
  create_array "system"
  create_array "p-dataflow" ","
  create_array "p-spring-cloud-services" ","
arr=$arr"]"
if [ "$TRACE_OFF" == "FALSE" ]; then
  printf "\nSpaces from 'system' Orgs: $arr \n"
fi

# Filter out all app in system org spaces
apps=$(cat ${PREFIX}_foundation.json | jq -r "$arr as \$system_spaces | {apps: [.[].apps[]? | select(.space as \$in | \$system_spaces | index(\$in) | not)]}")
echo $apps > ${PREFIX}_final_apps.json  
}

################################################
# READ_PAGES - Read CF API pages
# Parms: URL, FILE_NAME and JQ FILTER
################################################
read_pages() {

local API_URL=$1
local NAME=$2
local FILTER=$3
local TRACE_OFF=${4:-FALSE}

if [ "$TRACE_OFF" == "FALSE" ]; then
  echo "Reading pages... "
fi
# echo "$1 is the URL to call"
# echo "$2 is the file prefix"
# echo "$3 is the ja filter"

local next_url="${1}"
if [ "$TRACE_OFF" == "FALSE" ]; then
  echo $next_url
fi

local c=1

while [[ "${next_url}" != "null" ]]; do
  file_json=$(cf curl ${next_url}) 
  next_url=$(echo $file_json | jq -r -c ".next_url")
  file=$(echo $file_json | jq "[.resources[] | $FILTER]")
  echo $file > ${NAME}_page_${c}.json
  c=$((c + 1))
done
files=$(jq -s "{${NAME}: [.[][]]}" ${NAME}_page_*.json)
echo $files > ${PREFIX}_${NAME}.json
rm ${NAME}_page_*.json 
if [ "$TRACE_OFF" == "FALSE" ]; then
  echo "Done. Created file ${PREFIX}_${NAME}.json"
fi
}

###############################################
# CREATE_USERS - List all users into PREFIX_users.json
###############################################
create_users() {
  printf "\ncreating ${PREFIX}_users.json file...\n"
  read_pages "/v2/users?results-per-page=100" "users" "select (.entity.username | test(\"system_*|smoke_tests|admin|MySQL*|push_apps*\"; \"i\") | not)? | {username: .entity.username}"
}

###############################################
# CREATE_ORGS - List all organizations into PREFIX_orgs.json
###############################################
create_orgs() {
  printf "\ncreating ${PREFIX}_orgs.json file...\n"
  read_pages "/v2/organizations?results-per-page=100" "orgs" "{org_guid: .metadata.guid, name: .entity.name }"
}

###############################################
# CREATE_SPACES - List all spaces into PREFIX_spaces.json
###############################################
create_spaces() {
  printf "\ncreating ${PREFIX}_spaces.json file...\n"
  read_pages "/v2/spaces?results-per-page=100" "spaces" "{name: .entity.name, space_guid: .metadata.guid, org: .entity.organization_guid }"
}

###############################################
# CREATE_SERVICE - List all service brokers
###############################################
create_services() {
  printf "\ncreating ${PREFIX}_services.json file...\n"
  read_pages "/v2/services?results-per-page=100" "services" "{service_guid: .metadata.guid, label: .entity.label, service_broker_guid: .entity.service_broker_guid }"
}

###############################################
# CREATE_SERVICE_INSTANCES - List all service instances
###############################################
create_service_instances() {
  printf "\ncreating ${PREFIX}_service_instances.json file...\n"
  read_pages "/v2/service_instances?results-per-page=100" "service_instances" "{name: .entity.name, service_instance_guid: .metadata.guid, service_guid: .entity.service_guid, space_guid: .entity.space_guid }"
}

###############################################
# CREATE_USER_PROVIDED_SERVICE_INSTANCES - List all user provided service instances
###############################################
create_user_provided_service_instances() {
  printf "\ncreating ${PREFIX}_user_provided_service_instances.json file...\n"
  read_pages "/v2/user_provided_service_instances?results-per-page=100" "user_provided_service_instances" "{name: .entity.name, service_instance_guid: .metadata.guid, space_guid: .entity.space_guid }"
}

###############################################
# CREATE_SERVICE_BINDINGS - List all service bindings
###############################################
create_service_bindings() {
  printf "\ncreating ${PREFIX}_service_bindings.json file...\n"
  read_pages "/v2/service_bindings?results-per-page=100" "service_bindings" "{app_guid: .entity.app_guid , service_instance_guid: .entity.service_instance_guid}"
}

###############################################
# CREATE_APPS - List all apps into PREFIX_apps.json
###############################################
create_apps() {
  printf "\ncreating ${PREFIX}_apps.json file...\n"
  read_pages "/v2/apps?results-per-page=100" "apps" "{app_guid: .metadata.guid, name: .entity.name, memory: .entity.memory, state: .entity.state, instances: .entity.instances, buildpack:  (if .entity.buildpack == null then .entity.detected_buildpack else .entity.buildpack end), space: .entity.space_guid, updated: .entity.package_updated_at}"
}

###################
# CREATE_APP_SRV_BINDINGS - get apps binding
###################
create_app_srv_bindings() {

non_system_app TRUE

# echo "******* appguids - ${PREFIX}_final_apps.json"
apps_guids=$(cat ${PREFIX}_final_apps.json | jq -r ".apps[].app_guid")
rm ${PREFIX}_final_apps.json

# printf '%s\n' "${apps_guids[@]}"
total_apps=$(echo "${apps_guids[@]}" | wc -l)

printf "\nGenerating non system apps service bindings...\n\n"
c=0
while read -r line; do
    read_pages "/v2/apps/${line}/service_bindings?results-per-page=100" "apps_srv_binding_${c}" "{app_guid: .entity.app_guid, service_instance_guid: .entity.service_instance_guid, service_name: .entity.name}" TRUE
    c=$((c + 1))
    echo -ne "Apps read so far ${c} of ${total_apps}\r"
done <<< "$apps_guids"
printf "\nSearched for service bindings for ${c} apps.\n\n"

# Combine each app service bindings
jq --slurp . ${PREFIX}_apps_srv_binding_*.json > ${PREFIX}_apps_srv_binding.bkp
rm ${PREFIX}_apps_srv_binding_*.json 
mv ${PREFIX}_apps_srv_binding.bkp ${PREFIX}_apps_srv_binding.json
echo "Done. Created file ${PREFIX}_apps_srv_binding.json"

}

###################
# CREATE_TACKLE - create csv file for Tackle import
###################
create_tackle_app() {

echo "Record Type 1,Application Name,Description,Comments,Business Service,Dependency,Dependency Direction,Tag Type 1,Tag 1,Tag Type 2,Tag 2,Tag Type 3,Tag 3,Tag Type 4,Tag 4,Tag Type 5,Tag 5,Tag Type 6,Tag 6,Tag Type 7,Tag 7,Tag Type 8,Tag 8,Tag Type 9,Tag 9,Tag Type 10,Tag 10,Tag Type 11,Tag 11,Tag Type 12,Tag 12,Tag Type 13,Tag 13,Tag Type 14,Tag 14,Tag Type 15,Tag 15,Tag Type 16,Tag 16,Tag Type 17,Tag 17,Tag Type 18,Tag 18,Tag Type 19,Tag 19,Tag Type 20,Tag 20" > tackle_apps_${PREFIX}_import.csv

spaces_guids=$(jq -r ".[].spaces[]? | select(.name==\"${STAGE}\") | .space_guid" ${PREFIX}_foundation.json)
#printf '%s\n' "${spaces_guids[@]}"
#spaces_guids="7595fe1d-ba7e-47a6-a4e3-e5539d58a7c6"

total_spaces=$(echo "${spaces_guids[@]}" | wc -l)

i=0
while read -r line_space; do
  echo "******* get appguids for space_guid ${line_space}"
  org_id=$(jq -r ".[].spaces[]? | select(.space_guid==\"${line_space}\") | .org" ${PREFIX}_foundation.json)
  org=$(jq -r ".[].orgs[]? | select(.org_guid==\"${org_id}\") | .name" ${PREFIX}_foundation.json)
  apps_guids=$(jq -r ".[].apps[]? | select(.space==\"${line_space}\") | .app_guid" ${PREFIX}_foundation.json)
  
  #printf '%s\n' "${apps_guids[@]}"
  total_apps=$(echo "${apps_guids[@]}" | wc -l)

  printf "\nGenerating non system apps information ...\n\n"
  c=0
  while read -r line; do
    services=""
    app_name=$(jq -r ".[].apps[]? | select(.app_guid==\"${line}\") | .name" ${PREFIX}_foundation.json)

    service_ids=$(jq -r ".[].service_bindings[]? | select(.app_guid==\"${line}\") | .service_instance_guid" ${PREFIX}_foundation.json )  
    d=0
    if [[ "$service_ids" = *[!\ ]* ]]; then
      while read -r line_service; do
       instance_id=$(jq -r ".[].service_instances[]? | select(.service_instance_guid==\"${line_service}\") | .service_guid" ${PREFIX}_foundation.json)
       #echo "instance_id: $instance_id, line_service: $line_service"
       if [[ "$instance_id" = *[!\ ]* ]]; then
         tag_name=$(jq -r ".[].service_instances[]? | select(.service_instance_guid==\"${line_service}\") | .name" ${PREFIX}_foundation.json)
         tag_type=$(jq -r ".[].services[]? | select(.service_guid==\"${instance_id}\")  | .label" ${PREFIX}_foundation.json)
       else
         tag_name=$(jq -r ".[].user_provided_service_instances[]? | select(.service_instance_guid==\"${line_service}\") | .name" ${PREFIX}_foundation.json)
         tag_type="user_provided"
       fi
       services="${services} ${tag_type}:${tag_name}"
       #echo ${tag_name} $(grep -q "${tag_name}" tackle_apps_${PREFIX}_import.csv;echo $?)
      if [[ $(grep -q "1,S:${tag_name}," tackle_apps_${PREFIX}_import.csv;echo $?) -eq 1 ]] ; then
        echo "1,S:${tag_name},,,,,,application,${org},app type,service,service,${tag_type}" >> tackle_apps_${PREFIX}_import.csv
      fi 
      echo "2,A:${app_name},,,,S:${tag_name},northbound" >> tackle_apps_${PREFIX}_import.csv

      d=$((d + 1))
     done <<< "$service_ids"
    fi
    #echo "1,A:${app_name},,Services:${services},,,,application,${org},app type,app" >> tackle_apps_${PREFIX}_import.csv
    echo "1,A:${app_name},,,,,,application,${org},app type,app" >> tackle_apps_${PREFIX}_import.csv
    c=$((c + 1))
    echo -ne "Apps read so far ${c} of ${total_apps}\r"
  done <<< "$apps_guids"
  printf "\nSearched for service bindings for ${c} apps.\n\n"
  
  i=$((i + 1))
  echo "******* Spaces read so far ${i} of ${total_spaces}"
done <<< "$spaces_guids"

printf "\nDone. Created file tackle_${PREFIX}_import.csv\n"

printf "\nCreate a 'service' tag and the following tags needs to be created manually before import:\n"
jq -r ".[].services[]? | .label" ${PREFIX}_foundation.json
echo "user_provided"

printf "\nCreate a 'app type' tag type and the following tags needs to be created manually before import:\n"
echo "app"
echo "service"

printf "\nCreate a 'application' tag type and the following tags needs to be created manually before import:\n"
jq -r ".[].orgs[]? | .name" ${PREFIX}_foundation.json
}

###################
# CREATE_TACKLE - create csv file for Tackle import
###################
create_tackle_org() {

echo "Record Type 1,Application Name,Description,Comments,Business Service,Dependency,Dependency Direction,Tag Type 1,Tag 1,Tag Type 2,Tag 2,Tag Type 3,Tag 3,Tag Type 4,Tag 4,Tag Type 5,Tag 5,Tag Type 6,Tag 6,Tag Type 7,Tag 7,Tag Type 8,Tag 8,Tag Type 9,Tag 9,Tag Type 10,Tag 10,Tag Type 11,Tag 11,Tag Type 12,Tag 12,Tag Type 13,Tag 13,Tag Type 14,Tag 14,Tag Type 15,Tag 15,Tag Type 16,Tag 16,Tag Type 17,Tag 17,Tag Type 18,Tag 18,Tag Type 19,Tag 19,Tag Type 20,Tag 20" > tackle_org_${PREFIX}_import.csv

org_guids=$(jq -r ".[].orgs[]? | .org_guid" ${PREFIX}_foundation.json)
total_spaces=$(echo "${org_guids[@]}" | wc -l| tr -d '[:space:]')

i=0
while read -r line_org; do
  echo "******* get appguids for org_guid ${line_org}"
  space_id=$(jq -r ".[].spaces[]? | select(.org==\"${line_org}\" and .name==\"${STAGE}\") | .space_guid" ${PREFIX}_foundation.json)
  org=$(jq -r ".[].orgs[]? | select(.org_guid==\"${line_org}\") | .name" ${PREFIX}_foundation.json)
  apps_guids=$(jq -r ".[].apps[]? | select(.space==\"${space_id}\") | .app_guid" ${PREFIX}_foundation.json)
  
  #printf '%s\n' "${apps_guids[@]}"
  total_apps=$(echo "${apps_guids[@]}" | wc -l| tr -d '[:space:]')

  printf "\nGenerating non system apps information ...\n\n"
  c=0
  unset services
  declare -A services
  comment=""
  while read -r line; do
    app_name=$(jq -r ".[].apps[]? | select(.app_guid==\"${line}\") | .name" ${PREFIX}_foundation.json)
    printf -v comment "${comment}#${app_name//[[:space:]]/}"

    service_ids=$(jq -r ".[].service_bindings[]? | select(.app_guid==\"${line}\") | .service_instance_guid" ${PREFIX}_foundation.json )  
    unset services_pod
    declare -A services_pod

    if [[ "$service_ids" = *[!\ ]* ]]; then
      while read -r line_service; do
        instance_id=$(jq -r ".[].service_instances[]? | select(.service_instance_guid==\"${line_service}\") | .service_guid" ${PREFIX}_foundation.json)
        #echo "instance_id: $instance_id, line_service: $line_service"
        if [[ "$instance_id" = *[!\ ]* ]]; then
          service_name=$(jq -r ".[].service_instances[]? | select(.service_instance_guid==\"${line_service}\") | .name" ${PREFIX}_foundation.json)
          service_type=$(jq -r ".[].services[]? | select(.service_guid==\"${instance_id}\")  | .label" ${PREFIX}_foundation.json)
        else
          service_name=$(jq -r ".[].user_provided_service_instances[]? | select(.service_instance_guid==\"${line_service}\") | .name" ${PREFIX}_foundation.json)
          service_type="user_provided"
        fi
        services_pod[${service_type}]="${services_pod[${service_type}]} ${service_name//[[:space:]]/}"

        d=$((d + 1))
      done <<< "$service_ids"

      for service_type in "${!services_pod[@]}"; do
        # This adds the service names also to the comment.
        # we skip it for now as the comment is limmeted to 250 characters
        #printf -v comment "${comment};${service_type//[[:space:]]/}:${services_pod[$service_type]}"
        services[${service_type}]="${services[${service_type}]} ${services_pod[$service_type]}"
      done
    fi

    c=$((c + 1))
    echo -ne "Apps read so far ${c} of ${total_apps}\r"
  done <<< "$apps_guids"
  printf "\nSearched for service bindings for ${c} apps.\n\n"

  tags="pods,pods ${total_apps}"
  for service_type in "${!services[@]}"; do
    tags="${tags},${service_type},${service_type} "$(echo ${services[$service_type]}|wc -w|tr -d '[:space:]')
  done

  echo "Comment size: "$(echo ${comment}|wc -c|tr -d '[:space:]')
  echo "1,${org},Description,${comment},,,,${tags}" >> tackle_org_${PREFIX}_import.csv

  i=$((i + 1))
  echo "******* Spaces read so far ${i} of ${total_spaces}"
done <<< "$org_guids"

printf "\nDone. Created file tackle_${PREFIX}_import.csv\n"

printf "\nThe following 'Tag Types' needs to be created manually before import:\n"
jq -r ".[].services[]? | .label" ${PREFIX}_foundation.json
}


###############################################
# COMBINE_FILES Combine all json files into prefix_foundation.json
###############################################
combine_files() {
  jq --slurp . ${PREFIX}_*.json > ${PREFIX}_foundation.bkp
  rm ${PREFIX}_*.json 
  mv ${PREFIX}_foundation.bkp ${PREFIX}_foundation.json

  printf "\nCombined them into ${PREFIX}_foundation.json - I'm happy with this file.\n\n"
}


###############################################
# Helper functions
###############################################
jq_exists() {
  command -v jq >/dev/null 2>&1
}

error_and_exit() {
  echo "$1" && exit 1
}

###############################################
########## RUNNING ###############
###############################################

if [ "$#" -lt 1 ]; then
    usage_and_exit
fi

if ! jq_exists; then
    error_and_exit "jq command not found. Please install jq to support set-vm-type functionality (https://stedolan.github.io/jq/download/)"
fi

unset assoc
if ! declare -A assoc ; then
    printf "\n\nAssociative arrays not supported!\n"
    echo "Bash version 4 is required!"
    exit 1
fi

PREFIX=${1:-}
CMD=${2:-ALL}
STAGE=${3:-dev}

CMD=$( tr '[:lower:]' '[:upper:]' <<< "$CMD" )
echo "options: PREFIX: $PREFIX, CMD: $CMD , STAGE: $STAGE"

if [ "$CMD" == "SRVS" ]; then
  create_app_srv_bindings
elif [ "$CMD" == "APPS" ]; then
    create_csv
elif [ "$CMD" == "TACKLE_APP" ]; then
    create_tackle_app
elif [ "$CMD" == "TACKLE_ORG" ]; then
    create_tackle_org
elif [ "$CMD" == "ALL" ]; then
  # Created foundation file, needed for CSV step below
  create_orgs
  create_spaces
#  create_users
  create_apps
  create_services
  create_service_instances
  create_user_provided_service_instances
  create_service_bindings
  combine_files
else 
  echo "Invalid command $CMD"
  exit 1
fi
