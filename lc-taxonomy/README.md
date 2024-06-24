# Local Cosmos Docker project for the localcosmos.org taxonomy
The user of the database has to be "linneaus" (or according to the db dump you are using)

## Docker network
Live App Kits can only connect to live taxonomy.
Staging and Testing App Kits can connect to live and testing taxonomy.

Taxonomy has its own docker network lc-taxonomy-network (see docker-compose).
The App kit containers have to be part of this network (aside of their own network).

## How to use
example to run the docker container:

### live taxonomy
./compose_localcosmos_taxonomy.sh -c --taxonomy-network 172.20.250.0/24 --port 15432 --identifier live --password yourpassword

### testing taxonomy
./compose_localcosmos_taxonomy.sh -c --taxonomy-network 172.20.250.0/24 --port 25432 --identifier testing --password yourpassword

