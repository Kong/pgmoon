#!/bin/bash
set -e

# This script will configure postgres to accept SSL connections within the docker image
# Since it generates the key inside of the image, it requires the full postgres image and not an alpine linux variant

cd /var/lib/postgresql

ls -lah >&2

# SCRAM channel binding derives its hash from the algorithm the certificate is
# signed with, so both of them have to be configurable to test all of them
cert_digest=${PGMOON_TEST_CERT_DIGEST:-sha384}
cert_type=${PGMOON_TEST_CERT_TYPE:-rsa}

if [ "$cert_type" = "ec" ]; then
  openssl req -new -x509 -nodes -${cert_digest} -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout server.key -out server.crt -subj "/C=US/ST=Leafo/L=Leafo/O=Leafo/CN=itch.zone"
else
  openssl req -new -passout pass:itchzone -text -out server.req -subj "/C=US/ST=Leafo/L=Leafo/O=Leafo/CN=itch.zone"
  openssl rsa -passin pass:itchzone -in privkey.pem -out server.key
  rm privkey.pem
  openssl req -x509 -${cert_digest} -in server.req -text -key server.key -out server.crt
fi

chmod og-rwx server.key

# TLSv1 min version to mimic older versions of postgres

echo "
ssl = on
ssl_cert_file = '$(pwd)/server.crt'
ssl_key_file = '$(pwd)/server.key'
ssl_min_protocol_version = 'TLSv1'
password_encryption = 'scram-sha-256'
" >> data/postgresql.conf

# Store the password with scram-sha-256 so that the server negotiates
# SCRAM-SHA-256-PLUS and channel binding is exercised. Postgres images before
# 14 create the password with md5, and md5 in pg_hba.conf still upgrades to
# SCRAM when the stored password is a scram verifier
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-SQL
	SET password_encryption = 'scram-sha-256';
	ALTER USER "$POSTGRES_USER" PASSWORD '$POSTGRES_PASSWORD';
SQL
