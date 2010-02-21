#!/bin/bash

PATH=$PATH:/etc/bin

## Create temporary DB:

# drop tmp user
if [ $(psql -A -l|grep -c ^osmistmp) -gt 0 ]; then
    error-or-stfu dropdb osmistmp
    error-or-stfu dropuser osmistmp
fi

if [ $(psql -A -l|grep -c ^osmisdel) -gt 0 ]; then
    error-or-stfu dropdb osmisdel
    error-or-stfu dropuser osmisdel
fi

# Create db/user
#echo Creating user/db
error-or-stfu createuser osmistmp -w -S -D -R
error-or-stfu createdb -E UTF8 -O osmistmp osmistmp
echo "alter user osmistmp encrypted password 'osmistmp';" | error-or-stfu psql osmistmp

# Create schema
#echo Creating schema
error-or-stfu psql -d osmistmp < /usr/share/postgresql/8.4/contrib/btree_gist.sql
#psql -d osmistmp < /home/avar/src/osm.nix.is/osm-applications-utils-osmosis-trunk/script/contrib/apidb_0.6.sql

cd /home/avar/src/osm.nix.is/osm-sites-rails_port

echo "development:"           > config/database.yml
echo "  adapter: postgresql" >> config/database.yml
echo "  database: osmistmp"  >> config/database.yml
echo "  username: osmistmp"  >> config/database.yml
echo "  password: osmistmp"  >> config/database.yml
echo "  host: localhost"     >> config/database.yml
echo "  encoding: utf8"      >> config/database.yml

# migrate!
error-or-stfu nice -n 5 rake db:migrate

# Import Iceland.osm
#echo Importing data
error-or-stfu nice -n 5 osmosis \
    --read-xml-0.6 /var/www/osm.nix.is/latest/Iceland.osm.bz2 \
    --write-apidb-0.6 \
    populateCurrentTables=yes host="localhost" database="osmistmp" user="osmistmp" password="osmistmp" validateSchemaVersion=no

## Rename it & delete

# old -> del
#echo "Moving old -> del";
echo 'alter database osmis rename to osmisdel;' | error-or-stfu psql avar
echo 'alter user osmis rename to osmisdel;' | error-or-stfu psql avar

# tmp -> new
#echo "Moving tmp ->new"
echo 'alter database osmistmp rename to osmis;' | error-or-stfu psql avar
echo 'alter user osmistmp rename to osmis;' | error-or-stfu psql avar
echo "alter user osmis encrypted password 'osmis';" | error-or-stfu psql avar

# del old
error-or-stfu dropdb osmisdel
error-or-stfu dropuser osmisdel

# Regenerate munin stats
error-or-stfu sudo rm -v /var/lib/munin/plugin-state/osm_apidb_*storable
