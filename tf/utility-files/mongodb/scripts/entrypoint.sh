#!/bin/bash
#
# Note: If the script file was created on Windows, ensure the Linux EOL LF is used; otherwise, the
#       Windows EOL CRLF is used, and when the script is run on Linux, the shell will return an error.
#       To ensure the Linux EOL is used, open the script file with Notepad++ and then do the following:
#       View -> Show Symbol -> Show End of LIne
#       Edit -> EOL Conversion -> Unix (LF)

echo "### Advertised Hostname: $MONGODB_ADVERTISED_HOSTNAME ###"

# mongo /docker-entrypoint-initdb.d/start-replication.js
if [[ "$POD_NAME" = "mem-mongodb-0" ]]; then
  echo "### Pod name ($POD_NAME) matches initial primary pod name; configuring node as primary. ###"
  mongo --eval "printjson(rs.status())"
else
  echo "### Pod name ($POD_NAME) does not match initial primary pod name; configuring node as secondary. ###"
  mongo --eval "printjson(rs.status())"
fi

exit 0
