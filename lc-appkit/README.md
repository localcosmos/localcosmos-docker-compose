# docker-compose for running a complete Local Cosmos App Kit

## Prerequisites
Create the file ./django_settings.env and fill it with your values.
Read django settings docs at https://docs.djangoproject.com/en/4.2/ref/settings/

## Docker network
Live, staging and testing should live in different docker networks.
The taxonomic database (CoL) lives in its own network named lc-taxonomy-network.

## How to run

docker-compose up

Remember: 172.20.250.0/24 is the taxonomic network, so app kit networks start with 251

```
./compose_localcosmos.sh --identifier live --network 172.20.251.0/24 --ports-on-host 9001-9002  --taxon-db live --pg-user yourpguser --pg-password yourpassword 
```

```
./compose_localcosmos.sh --identifier staging --network 172.20.252.0/24 --ports-on-host 9101-9102 --taxon-db live --pg-user yourpguser --pg-password yourpassword
```

```
./compose_localcosmos.sh --identifier testing --network 172.20.253.0/24 --ports-on-host 9201-9202 --taxon-db live --pg-user yourpguser --pg-password yourpassword
```

## Clone data for staging
```
./compose_localcosmos.sh --identifier staging --network 172.20.252.0/24 --ports-on-host 9101-9102 --taxon-db live --pg-user yourpguser --pg-password yourpassword --clone-data
```

## Delete data for testing
```
./compose_localcosmos.sh --identifier testing --network 172.20.253.0/24 --ports-on-host 9201-9202 --taxon-db live --pg-user yourpguser --pg-password yourpassword --delete-data
```