#!/bin/bash

# Default values
CONTAINER_BASENAME=lc-taxonomy-database
TAXONOMY_NETWORK=10.3.5.0/24
CD_IDENTIFIER=-live
DB_PORT_EXTERNAL=15432
# It is required to ste the password using --password
DB_PASSWORD=password
TEMP_YAML_FILE="localcosmos-taxonomy-docker-compose.yml"

CLEAR=false

# Possible override by command line parameters for customization
optspec=":ci-:"
while getopts "$optspec" optchar; do
  case "${optchar}" in
    -)
      case "${OPTARG}" in
        identifier)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          CD_IDENTIFIER=-$val
          ;;
        taxonomy-network)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          TAXONOMY_NETWORK=$val
          ;;
        port)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
           echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
           DB_PORT_EXTERNAL=$val
           ;;
        password)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          DB_PASSWORD=$val
          ;;
        esac;;
    c)
      CLEAR=true
      ;;
  esac
done

clean_temporary_files () {
  if [ -n "$TEMP_YAML_FILE" ]; then
    if [[ -f $TEMP_YAML_FILE ]]; then
      echo "File exists at $TEMP_YAML_FILE. Removing"
      rm -f "$TEMP_YAML_FILE"
    fi
  fi

}

if [[ "$DB_PASSWORD" == "password" ]]; then
  echo -e "\nERROR: You have to set a valid --db-password"
  exit 1
fi

NETWORK_NAME=lc-taxonomy-network

# check if the localcosmos docker taxonomy network is present
info=`docker network inspect ${NETWORK_NAME}`
if [[ "[]" == $info ]]
then
  docker network create ${NETWORK_NAME} --driver=bridge --subnet=${TAXONOMY_NETWORK}
fi

if [[ $CLEAR == true ]]; then
  # Remove any existing database container and its volumes
  docker stop ${CONTAINER_BASENAME}${CD_IDENTIFIER} 2>/dev/null || true
  docker rm -v ${CONTAINER_BASENAME}${CD_IDENTIFIER} 2>/dev/null || true
fi

clean_temporary_files

# Replace variables in docker-compose.yml and start up the new database
ymlContent=$(sed -e 's#$DB_PASSWORD#'$DB_PASSWORD'#g' \
    -e 's#$DB_PORT_EXTERNAL#'$DB_PORT_EXTERNAL'#g' \
    -e 's#$CONTAINER_BASENAME#'$CONTAINER_BASENAME'#g' \
    -e 's#$CD_IDENTIFIER#'$CD_IDENTIFIER'#g' \
    -e 's#$TAXONOMY_NETWORK#'$TAXONOMY_NETWORK'#g' \
    docker-compose.yml)

echo "$ymlContent" > "$TEMP_YAML_FILE"

docker compose -f "$TEMP_YAML_FILE" -p ${CONTAINER_BASENAME}${CD_IDENTIFIER} up -d
rc=$?; 

if [[ $rc != 0 ]]; then
    exit $rc;
fi

exit 0
