#!/bin/bash

: "${XDMOD_ORGANIZATION_NAME:="Example Organization"}"
: "${XDMOD_ORGANIZATION_ABBREV:="example-org"}"

set -o errexit -o nounset

LOG() {
	echo "$(date "+%Y-%m-%d %H:%M:%S") ${0##*/}: $*" >&2
}

DIE() {
	LOG "ERROR: $1"
	exit "${2:-1}"
}

[ -d /etc/xdmod ] || DIE "missing xdmod configuration directory"

# If the configuration directory is empty, copy in the default configuration
# files.
if [ ! -f /etc/xdmod/portal_settings.ini ]; then
	LOG "initializing xdmod configuration"
	tar -C /etc/xdmod.orig -cf - . | tar -C /etc/xdmod -xf-
fi

# Copy any files found in /config/xdmod into /etc/xdmod (this allows us
# to expose static configuration via configmap mounts or bind mounts)
[ -d /config/xdmod ] && for fn in /config/xdmod/*; do
	[ -f "$fn" ] || continue
	LOG "installing $fn tp /etc/xdmod"
	install -m 644 "$fn" /etc/xdmod/
done

LOG "configuring database access parameters"
PORTAL_SETTINGS=/etc/xdmod/portal_settings.ini
for section in database datawarehouse shredder hpcdb logger; do
	crudini --verbose --set "$PORTAL_SETTINGS" "$section" host "${XDMOD_DB_HOST}"
	crudini --verbose --set "$PORTAL_SETTINGS" "$section" port "${XDMOD_DB_PORT}"
	crudini --verbose --set "$PORTAL_SETTINGS" "$section" user "${XDMOD_DB_USER}"
	crudini --verbose --set "$PORTAL_SETTINGS" "$section" pass "${XDMOD_DB_PASSWORD}"
done

# This sections sets configuration values in portal_settings.ini from
# environment variables. For example, if you wanted to set the
# "debug_mode" option in the "general" section to "true", you would set:
#
#   XDMOD_PORTAL_SETTINGS_GENERAL__DEBUG_MODE=true 
#
# (Note the double underscore __ used to separate the section name from the
# option name.)
LOG "configuring portal_settings.ini"
for var in $(set | grep XDMOD_PORTAL_SETTINGS_ | cut -f1 -d=); do
	# strip prefix
	base="${var#XDMOD_PORTAL_SETTINGS_}"

	# split on section delimiter (__)
	# shellcheck disable=2206
	varspec=(${base//__/ })
	crudini --verbose --set "$PORTAL_SETTINGS" "${varspec[0],,}" "${varspec[1],,}" "${!var}"
done

# Store database credentials in a my.cnf file so that we can use them
# in subsequent commands.
cat > /etc/xdmod/my.cnf <<EOF
[client]
user=$XDMOD_DB_USER
password=$XDMOD_DB_PASSWORD
EOF

# Set up common mysql command line arguments
DBARGS=( --defaults-extra-file=/etc/xdmod/my.cnf --host="$XDMOD_DB_HOST" )

# wait for mariadb to respond
#
# Run `mysqladmin ping` in a loop until it succeeds. This lets us know that
# mysql is ready to accept connections.
while ! mysqladmin "${DBARGS[@]}" ping > /dev/null; do
	LOG "waiting for database service"
	sleep 2
done

# check if database was previously initialized
#
# We check for the `log_id_seq` table in the `mod_logger` database to detect
# whether or not we have previously run database initializations. If not, we
# wrap xdmod-setup with an expect script that will (re-)create all the
# databases.
if ! mysql "${DBARGS[@]}" --database mod_logger --execute 'select 1 from log_id_seq' > /dev/null; then
	LOG "initializing database"
	expect -f /docker/xdmod-setup-init-databases.expect
	LOG "finished initializing database"
else
	LOG "skipping database initialization (database was previously initialized)"
fi

# Create the admin user if it has not already been created.
if [ -n "$XDMOD_ADMIN_USERNAME" ]; then
	if ! mysql "${DBARGS[@]}" --database moddb  \
			--execute "select 'exists' from Users where username='${XDMOD_ADMIN_USERNAME}'"  \
			--raw --batch -N | grep exists; then
		LOG "creating admin user"
		expect -f /docker/xdmod-setup-create-admin-user.expect
	fi
fi

LOG "finished runtime initialization"

exec "$@"
