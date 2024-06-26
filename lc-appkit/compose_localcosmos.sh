#!/bin/bash
#########################################################################################
# Script to start or update the Local Cosmos App Kit application.
# It will use the docker-compose.yml file to load the application and run it as daemon.
# It supports testing, staging and live deployments
# This does not cover the installation of taxonomic databases.
# It DOES cover which taxonomic database (live or testing) to connect to.
#########################################################################################

PROJECT_NAME=localcosmosorg
CD_IDENTIFIER=-live
LOCALCOSMOS_NETWORK=172.20.250.0/24
LC_PORTS_ON_HOST=9090-9091
TAXON_DB=-live
DELETE_DATA=false
CLONE_LIVE_DATA=false
REBUILD_DATABASE_CONTAINER=false
POSTGRES_USER=user
POSTGRES_PASSWORD=password

# Function to print usage information
usage() {
    cat <<EOF
Usage: $0 [options]
Options:
  --project-name <name>         Set project name
  --identifier <identifier>     Set CD identifier
  --network <network>           Set local cosmos network
  --ports-on-host <ports>       Set local cosmos ports on host
  --taxon-db <db>               Set taxonomic database
  --pg-password <password>      Set PostgreSQL password
  --clone-data                  Enable cloning of live data
  --delete-data                 Enable deletion of data
  --rebuild-database-container  Enable rebuilding of database container
EOF
    exit 1
}

echo "Starting Local Cosmos"

optspec=":p:i:n:t:d:c:r-:"
while getopts "$optspec" optchar; do
  case "${optchar}" in
    -)
      case "${OPTARG}" in
        project-name)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          PROJECT_NAME=$val
          ;;
        identifier)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          CD_IDENTIFIER=-$val
          ;;
        network)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          LOCALCOSMOS_NETWORK=$val
          ;;
        ports-on-host)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          LC_PORTS_ON_HOST=$val
          ;;
        taxon-db)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          TAXON_DB=-$val
          ;;
        pg-user)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          POSTGRES_USER=$val
          ;;
        pg-password)
          val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
          echo "Parsing option: '--${OPTARG}', value: '${val}'" >&2;
          POSTGRES_PASSWORD=$val
          ;;
        clone-data)
          echo "Setting '--${OPTARG}' to true" >&2;
          CLONE_LIVE_DATA=true
          ;;
        delete-data)
          echo "Setting '--${OPTARG}' to true" >&2;
          DELETE_DATA=true
          ;;
        rebuild-database-container)
          echo "Setting '--${OPTARG}' to true" >&2;
          REBUILD_DATABASE_CONTAINER=true
          ;;
        *)
          echo "Invalid option: --$OPTARG"
          exit 1
          ;;
      esac
  esac
done

if [[ "$POSTGRES_PASSWORD" == "password" ]]; then
  echo -e "\nERROR: You have to set a valid --pg-password"
  exit 1
fi

if [[ "$POSTGRES_USER" == "user" ]]; then
  echo -e "\nERROR: You have to set a valid --pg-user"
  exit 1
fi

echo "Removing dangling docker containers"
docker rm $(docker ps -a -f status=exited -f status=created -q)

if [[ $CLONE_LIVE_DATA == true ]];
then
  if [[ $CD_IDENTIFIER != '-staging' ]]; then
    echo "Only staging builds support cloning of live data. You passed the identifier $CD_IDENTIFIER. Aborting."
    exit 1;
  fi
fi

if [[ $DELETE_DATA == true ]];
then
  if [[ $CD_IDENTIFIER != '-staging' ]] && [[ $CD_IDENTIFIER != '-testing' ]]; then
    echo "Only staging and testing builds support data deletion. You passed the identifier $CD_IDENTIFIER. Aborting."
    exit 1;
  fi
fi

TAXONOMY_NETWORK_NAME=lc-taxonomy-network

# check if the localcosmos docker network is present
echo "Checking the taxonomic network"
info=`docker network inspect ${TAXONOMY_NETWORK_NAME}`
if [[ "[]" == $info ]]
then
  echo -e "\nERROR: Network $TAXONOMY_NETWORK_NAME not found. Did you run compose_localcosmos_taxonomy.sh ?"
  exit 1
fi

# create a yaml file with appropriate parameters
create_docker_compose_yaml () {

  # Create the yml file, replace with passed arguments
  local ymlContent=`sed -e 's#$CD_IDENTIFIER#'$CD_IDENTIFIER'#g' \
    -e 's#$LC_PORTS_ON_HOST#'$LC_PORTS_ON_HOST'#g' \
    -e 's#$LOCALCOSMOS_NETWORK#'$LOCALCOSMOS_NETWORK'#g' \
    -e 's#$TAXON_DB#'$TAXON_DB'#g' \
    -e 's#$POSTGRES_USER#'$POSTGRES_USER'#g' \
    -e 's#$POSTGRES_PASSWORD#'$POSTGRES_PASSWORD'#g' \
    docker-compose.yml`

  echo "$ymlContent"
}

wait_for_container () {
  # Set to name or ID of the container to be watched.
  CONTAINER_ID=$1

  # Default container state is set to "Running"
  CONTAINER_STATE=${2:-Running}

  echo "State of container $CONTAINER_ID: $CONTAINER_STATE"

  # Set timeout to the number of seconds you are willing to wait.
  timeout=120
  counter=0

  # Print the initial waiting message
  echo -n "Waiting for $CONTAINER_ID to be ready (${counter}/${timeout})"

  # This loop will continue until the container is in the desired state or timeout occurs.
  until [[ $(docker inspect --format "{{json .State.$CONTAINER_STATE}}" $CONTAINER_ID) == true ]]; do
    # If timeout is reached, exit with an error message
    if (( counter >= timeout )); then
      echo -e "\nERROR: Timed out waiting for $CONTAINER_ID to come up."
      exit 1
    fi

    # Every 5 seconds update the status
    if (( counter % 5 == 0 )); then
      echo -ne "\rWaiting for $CONTAINER_ID to be ready (${counter}/${timeout})"
    fi

    # Wait a second and increment the counter
    sleep 1
    ((counter++))
  done

  echo -e "\nContainer $CONTAINER_ID is running."
}

# Create the docker compose projectname, strip all - and _ characters 
DOCKER_PROJECTNAME=`echo ${PROJECT_NAME}${CD_IDENTIFIER} | sed  s/[-_]//g`
echo -e "\nDocker project name: $DOCKER_PROJECTNAME"


if [[ $DELETE_DATA == true ]] || [[ $CLONE_LIVE_DATA == true ]]; then
  # Remove any existing database container
  docker stop lc-database$CD_IDENTIFIER ; docker rm -v lc-database$CD_IDENTIFIER

  # get staging containers and remove them
  SERVICE_NAME=lc-appkit
  CONTAINER_BASENAME=$DOCKER_PROJECTNAME-$SERVICE_NAME
  STAGING_CONTAINER_1_ID=$(docker ps -f name=$CONTAINER_BASENAME -q | head -n1)
  STAGING_CONTAINER_2_ID=$(docker ps -f name=$CONTAINER_BASENAME -q | tail -n1)
  
  echo "Stopping and removing staging container (${CONTAINER_BASENAME}) 1: ${STAGING_CONTAINER_1_ID}"
  docker stop $STAGING_CONTAINER_1_ID ; docker rm -v $STAGING_CONTAINER_1_ID

  if [[ "$STAGING_CONTAINER_1_ID" == "$STAGING_CONTAINER_2_ID" ]]; then
    echo "Did not find a second staging container"
  else
    echo "Stopping and removing staging container 2: ${STAGING_CONTAINER_2}"
    docker stop $STAGING_CONTAINER_2_ID ; docker rm -v $STAGING_CONTAINER_2_ID
  fi
  
  # remove volumes
  echo "Removing the named volumes of the database"
  docker volume rm ${DOCKER_PROJECTNAME}_database_data
  docker volume rm ${DOCKER_PROJECTNAME}_database_log

  echo "Removing named volumes of the app kit container"
  docker volume rm ${DOCKER_PROJECTNAME}_apps
  docker volume rm ${DOCKER_PROJECTNAME}_www
  docker volume rm ${DOCKER_PROJECTNAME}_private_frontends

  echo "Removing the network ${DOCKER_PROJECTNAME}_lc-network"
  docker network rm ${DOCKER_PROJECTNAME}_lc-network
fi

# Clone the data if requested. We cannot do this after docker compose created the volumes itself
# because the database would not work then.
# This creates a warning: "Use `external: true` to use an existing volume"
# A solution without a warning would be preferred
# https://github.com/gdiepen/docker-convenience-scripts

if [[ $CLONE_LIVE_DATA == true ]];
then
  if [[ $CD_IDENTIFIER == '-staging' ]];
  then
    # clone the 2 database volumes
    echo "Cloning live named volumes of the database"
    source ./docker_clone_volume.sh ${PROJECT_NAME}live_database_log ${DOCKER_PROJECTNAME}_database_log
    source ./docker_clone_volume.sh ${PROJECT_NAME}live_database_data ${DOCKER_PROJECTNAME}_database_data
  
    # clone the 2 appkit volumes
    echo "Cloning live named volumes of the web container"
    source ./docker_clone_volume.sh ${PROJECT_NAME}live_www ${DOCKER_PROJECTNAME}_www
    source ./docker_clone_volume.sh ${PROJECT_NAME}live_apps ${DOCKER_PROJECTNAME}_apps
    source ./docker_clone_volume.sh ${PROJECT_NAME}live_private_frontends ${DOCKER_PROJECTNAME}_private_frontends
  fi
fi

#### STARTING THE DATABASE
# the database container is only started if the REBUILD_DATABASE_CONTAINER flag is set to true or 
# if the container does not exists yet. This does not delete any volumes.
DATABASE_CONTAINER_NAME=lc-database$CD_IDENTIFIER
DATABASE_CONTAINER_ID=$(docker ps -f name=$DATABASE_CONTAINER_NAME -q | head -n1)

if  [[ -z "$DATABASE_CONTAINER_ID" ]]; then
  echo -e "\nNo database container found, starting it"
  ymlContent=$(create_docker_compose_yaml)
  echo "$ymlContent" | docker compose -f - --project-name ${DOCKER_PROJECTNAME} up -d --no-deps --no-recreate lc-database
fi

DATABASE_CONTAINER_ID=$(docker ps -f name=$DATABASE_CONTAINER_NAME -q | head -n1)

# wait for the database container to be ready
echo "Waiting for database container: $DATABASE_CONTAINER_ID"
wait_for_container $DATABASE_CONTAINER_ID

sleep 5

# run the database migration and wait until it is finished
# it is finished when the container exited
migrate () {
  MIGRATION_CONTAINER_NAME=lc-migration$CD_IDENTIFIER
  MIGRATION_CONTAINER_ID=$(docker ps -f name=$MIGRATION_CONTAINER_NAME -q | head -n1)

  if  [[ -n "$MIGRATION_CONTAINER_ID" ]]; then
    echo "Migration container found"
    MIGRATION_CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' $MIGRATION_CONTAINER_NAME)
    echo "Status of $MIGRATION_CONTAINER_NAME: $MIGRATION_CONTAINER_STATUS"
    # if the container has exited, remove it.
    if [ "$MIGRATION_CONTAINER_STATUS" = "exited" ] || [ "$MIGRATION_CONTAINER_STATUS" == "created" ]; then
      echo "Removing $MIGRATION_CONTAINER_STATUS container $MIGRATION_CONTAINER_NAME"
      docker rm $MIGRATION_CONTAINER_ID
    else
      echo "Found migration container $MIGRATION_CONTAINER_NAME with status $MIGRATION_CONTAINER_STATUS. Aborting."
      exit 1;
    fi
  else
    echo "Migrating"
    ymlContent=$(create_docker_compose_yaml)
    echo "$ymlContent" | docker compose -f - --project-name ${DOCKER_PROJECTNAME} up -d --no-deps --no-recreate migration
    # wait for the container to finish
    counter=0
    timeout=120
    until [[ $(docker inspect -f '{{.State.Status}}' $MIGRATION_CONTAINER_NAME) == "exited" ]]; do
      if (( counter >= timeout )); then
        echo -e "\nERROR: Timed out waiting for $MIGRATION_CONTAINER_NAME to exit."
        exit 1
      fi

      # Every 5 seconds update the status
      if (( counter % 5 == 0 )); then
        echo -ne "\rWaiting for $MIGRATION_CONTAINER_NAME to be finished (${counter}/${timeout})"
      fi

      # Wait a second and increment the counter
      sleep 1
      ((counter++))
    done

    exit_status=$(docker inspect -f '{{.State.ExitCode}}' $MIGRATION_CONTAINER_NAME)
    if [[ $(docker inspect -f '{{.State.ExitCode}}' $MIGRATION_CONTAINER_NAME) == 1 ]];
    then
      echo -e "\nError during migration. Exiting"
      exit 1;
    fi
    echo -e "\nFinished migrating database"
  fi
}

if [[ $CLONE_LIVE_DATA == true ]]; then
  echo "Skipping migration, cloning data later"
else
  migrate
fi


#### DEPLOYING WITH ZERO DOWNTIME
# This part starts or deploys an lc-appkit service
# the service lc-database only is started if it is not running yet

# helper function for stopping a docker container by id
stop_appkit_container () {
  container_id=$1
  echo "Stopping and removing old container ${container_id}."
  docker stop $container_id
  docker rm $container_id
}

scale_appkit_container () {
  SERVICE_NAME=$1
  # create the folder for the uwsgi socket if it doesn ot exist
  echo "Start up the localcosmos environment $SERVICE_NAME"
  ymlContent=$(create_docker_compose_yaml)
  echo "$ymlContent" | docker compose -f - --project-name ${DOCKER_PROJECTNAME} up -d --no-deps --scale ${SERVICE_NAME}=2 --no-recreate ${SERVICE_NAME}
  echo "$ymlContent" | docker compose -f - --project-name ${DOCKER_PROJECTNAME} up -d --no-deps --scale ${SERVICE_NAME}=2 --no-recreate ${SERVICE_NAME}
}

deploy_localcosmos () {

  SERVICE_NAME=lc-appkit

  CONTAINER_BASENAME=$DOCKER_PROJECTNAME-$SERVICE_NAME

  CONTAINER_1_ID=$(docker ps -f name=$CONTAINER_BASENAME -q | tail -n1)
  CONTAINER_2_ID=$(docker ps -f name=$CONTAINER_BASENAME -q | head -n1)

  echo "container 1 id: $CONTAINER_1_ID; container 2 id: $CONTAINER_2_ID"

  if [[ ! -z "$CONTAINER_1_ID" ]] && [[ "$CONTAINER_1_ID" == "$CONTAINER_2_ID" ]];
  then
    echo "Only one container found."
    unset CONTAINER_2_ID;
  fi

  # if container_2 exists, stop it
  if [[ ! -z "$CONTAINER_2_ID" ]]; then
    echo "Found container_2 with id ${CONTAINER_2_ID}. Stopping it."
    stop_appkit_container $CONTAINER_2_ID
  fi

  if [[ -z "$CONTAINER_1_ID" ]]; then
    echo "Found neither container_1 nor container_2. Starting 2 containers."
    scale_appkit_container $SERVICE_NAME
  else
    # restart container_2 with new image
    echo "Found container_1 with id ${CONTAINER_1_ID}."
    echo "Starting container_2 with current image."
    scale_appkit_container $SERVICE_NAME

    # wait for container_2 to become available. Make sure it is the correct id.
    CONTAINER_2_NEW_ID=$(docker ps -f name=$CONTAINER_BASENAME -q | head -n1)

    if [[ "$CONTAINER_2_NEW_ID" == "$CONTAINER_1_ID" ]]; then
      CONTAINER_2_NEW_ID=$(docker ps -f name=$CONTAINER_BASENAME -q | tail -n1)
    fi

    if [[ "$CONTAINER_2_NEW_ID" == "$CONTAINER_1_ID" ]]; then
      echo "Did not fin ID for second container"
      exit 1;
    fi

    echo "Found container_2 new id: ${CONTAINER_2_NEW_ID}."

    # looking up the new ip has to be done in the correct network
    # app kit contianers are in 2 networks: their own network and the taxonomy network
    #CONTAINER_2_NEW_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_2_NEW_ID)
    CONTAINER_2_NEW_IP=$(docker inspect -f '{{range $i, $v :=  .NetworkSettings.Networks}}{{if eq $i "lc-taxonomy-network" }}{{else}}{{.IPAddress}}{{end}}{{end}}' $CONTAINER_2_NEW_ID)

    if  [[ -z "$CONTAINER_2_NEW_IP" ]]; then
      echo "Did not find IP of container 2. Is it running?"
      exit 1
    fi

    echo "New IP of container 2: $CONTAINER_2_NEW_IP"
    # 8000 is the nginx port inside the docker container
    # the --fail flag does not work with django_tenants, because the IP will not be recognized as a tenant and return 404
    # curl --silent --include --retry-connrefused --retry 30 --retry-delay 1 --fail http://$CONTAINER_2_NEW_IP:8000/ || exit 1
    curl --silent --include --retry-connrefused --retry 30 --retry-delay 1 http://$CONTAINER_2_NEW_IP:8000/ || exit 1

    # container_2 is available, stop and start container 1
    echo "Stopping container $CONTAINER_1_ID"
    stop_appkit_container $CONTAINER_1_ID
    # start container_1
    #docker compose up -d --no-deps --scale $SERVICE_NAME=2 --no-recreate $SERVICE_NAME
    echo "Scaling app-kit service"
    scale_appkit_container $SERVICE_NAME

  fi

  echo "Done."
}

deploy_localcosmos

echo "Removing dangling docker containers"
docker rm $(docker ps -a -f status=exited -f status=created -q)

exit $?