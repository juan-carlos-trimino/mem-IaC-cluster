#!/bin/bash
#
# Note: If the script file was created on Windows, ensure the Linux EOL LF is used; otherwise, the
#       Windows EOL CRLF is used, and when the script is run on Linux, the shell will return an error.
#       To ensure the Linux EOL is used, open the script file with Notepad++ and then do the following:
#       View -> Show Symbol -> Show End of LIne
#       Edit -> EOL Conversion -> Unix (LF)
#

echo "* Advertised Hostname: $MONGODB_ADVERTISED_HOSTNAME"

if [[ "$POD_NAME" = "mem-mongodb-0" ]]; then
  echo "* Pod name ($POD_NAME) matches initial primary pod name; configuring node as primary."
  export MONGODB_REPLICA_SET_MODE="primary"
else
  echo "* Pod name ($POD_NAME) does not match initial primary pod name; configuring node as secondary."
  export MONGODB_REPLICA_SET_MODE="secondary"
  export MONGODB_INITIAL_PRIMARY_PORT_NUMBER="$MONGODB_PORT_NUMBER"
  # export MONGODB_INITIAL_PRIMARY_ROOT_PASWORD="$MONGODB_ROOT_PASSWORD"
fi

exec /usr/local/bin/docker-entrypoint.sh mongod
# exit 0
