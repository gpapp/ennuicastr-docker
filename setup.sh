#!/bin/bash
PWD=$(pwd)
if [ ! -e ${PWD}/.env ]; then
	cp .env.template .env
	echo "PLEASE SET UP THE ENVIRONMENT VARIABLES IN ENV TO PROCEED!!" >&2
	exit
fi
sed -r 's+(^[~=])*=[ \t]*([^"].*)+\1="\2"+;/^#/d;/^$/d' .env >.bashenv;source .bashenv;rm .bashenv
if [ ! -e /etc/ufw/applications.d/ennuicastr ]; then
	cp ufw/ennuicastr /etc/ufw/applications.d/
	ufw allow ennuicastr
fi
if [ -z "$JVB_AUTH_PASSWORD" ]; then
	curl https://raw.githubusercontent.com/jitsi/docker-jitsi-meet/master/gen-passwords.sh -o ${PWD}/gen-passwords.sh
	chmod +x ${PWD}/gen-passwords.sh
	${PWD}/gen-passwords.sh
	rm ${PWD}/gen-passwords.sh
fi
if [ ! -e ${PWD}/run/web/ennuicastr/config.json.example ]; then
	mkdir -p ${PWD}/run/web/ennuicastr
	chown www-data.www-data -R ${PWD}/run/web/ennuicastr/
	curl https://raw.githubusercontent.com/gpapp/ennuicastr-server/master/config.json.example -o ${PWD}/run/web/ennuicastr/config.json.example
fi

if [ ! -e ${PWD}/run/prosody ]; then
    mkdir -p ${PWD}/run/{web/crontabs,web/logs,transcripts,prosody/config/data,prosody/prosody-plugins-custom,jicofo,jvb}

    chown www-data.www-data -R  ${PWD}/run/
    chown 101.102 -R  ${PWD}/run/prosody
fi

sed -r \
"s+https://ennuicastr.com+https://${PUBLIC_SITE}+g;
 s+r.ennuicastr.com+${PUBLIC_SITE}/rec+g;
 s+l.ennuicastr.com+${PUBLIC_SITE}/rec/lobby+g;
 s+ez.ennuicastr.com+${PUBLIC_SITE}/ennuizel+g;
 s+~/cert+/external/cert+g;
 s+~/ennuicastr-server/(db|rec|sound)+/external/\1+g; 
 s+~/ennuicastr+/ennuicastr+g; 
 /google/ {n;s+\"\"+\"${GOOGLE_CLIENT_ID}\"+g;n;s+\"\"+\"${GOOGLE_CLIENT_SECRET}\"+g;}; 
 /paypal/ {n;s+api.paypal+api.sandbox.paypal+;n;s+\"\"+\"${PAYPAL_CLIENT_ID}\"+;n;s+\"\"+\"${PAYPAL_CLIENT_SECRET}\"+;n;s+: \".*\"+: ${PAYPAL_SUBSCRIPTION}+;}; 
" \
${PWD}/run/web/ennuicastr/config.json.example > ${PWD}/run/web/ennuicastr/config.json

#docker-compose down
docker-compose stop web
docker-compose pull
docker-compose build
docker-compose up --no-start

## COPY CERTIFICATES needed to open WS server sockets directly 
if [ ! -e ${PWD}/run/web/ennuicastr/cert ]; then
  mkdir -p ${PWD}/run/web/ennuicastr/cert
  cp /etc/letsencrypt/live/${PUBLIC_SITE}/fullchain.pem ${PWD}/run/web/ennuicastr/cert
  cp /etc/letsencrypt/live/${PUBLIC_SITE}/privkey.pem ${PWD}/run/web/ennuicastr/cert
  chown www-data.www-data -R  ${PWD}/run/web/ennuicastr
fi
mkdir -p ${PWD}/run/web/nginx/site-confs/
sed -r "s+\\$\\{PUBLIC_SITE\\}+${PUBLIC_SITE}+g;" ${PWD}/jitsi-ennuicastr/config/site-confs/jitsi.conf > ${PWD}/run/web/nginx/site-confs/jitsi.conf
chown www-data -R ${PWD}/run/web/

# set up hosts for nginx
rm ${PWD}/run/web/logs/*
ln -s /var/log/nginx/*castr.*.*-*.log ${PWD}/run/web/logs

sed -r \
"s+ennuicastr.com+${PUBLIC_SITE}+g;
 s+r.ennuicastr.com+${PUBLIC_SITE}/rec+g;
 s+l.ennuicastr.com+${PUBLIC_SITE}/rec/lobby+g;
 s+ez.ennuicastr.com+${PUBLIC_SITE}/ennuizel+g;
" \
${PWD}/nginx/nginx.conf.template > ${PWD}/nginx/nginx.conf

docker-compose start web

#initialize DB
if [ ! -e ${PWD}/run/web/ennuicastr/db ]; then
  docker-compose exec web sh -c " \
    mkdir -p /external/db; \
    cd /external/db; \
    sqlite3 ennuicastr.db < /ennuicastr-server/db/ennuicastr.schema;\
    sqlite3 log.db < /ennuicastr-server/db/log.schema;\
    chown www-data.www-data *.db
    sed -ri 's+server_name.*$+server_name ${PUBLIC_SITE}\;+g' /defaults/meet.conf; 
  "
  mkdir -p ${PWD}/run/web/ennuicastr/rec
  mkdir -p ${PWD}/run/web/ennuicastr/sounds
  chown www-data.www-data -R  ${PWD}/run/web/ennuicastr
fi

# TODO: needs to match docker-compose prefix!!!
docker cp .env ennuicastr_web_1:/var/www/html/.env
docker-compose exec web sh -c "
    sed -ri  's+server_name.*$+server_name ${PUBLIC_SITE}\;+g' /defaults/meet.conf; \
# patch the WS root to get rid of virtualhosts and link everything to default
    sed -ri 's/^root.*$//g' /ennuicastr-server/njsp/njsp.js; \
    ln -s /ennuicastr-server/ws/client/* /ennuicastr-server/ws/rtennui/* /ennuicastr-server/ws/default/; \
    curl 'https://weca.st/libav/libav-3.6b.4.4.1-ennuicastr.js'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/libav/libav-3.6.4.4.1-ennuicastr.js && \
    curl 'https://weca.st/libav/libav-3.6b.4.4.1-ennuicastr.asm.js'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/libav/libav-3.6.4.4.1-ennuicastr.asm.js && \
    curl 'https://weca.st/libav/libav-3.6b.4.4.1-ennuicastr.wasm.js'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/libav/libav-3.6.4.4.1-ennuicastr.wasm.js && \
    curl 'https://weca.st/libav/libav-3.6b.4.4.1-ennuicastr.wasm.wasm'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/libav/libav-3.6.4.4.1-ennuicastr.wasm.wasm && \
    curl 'https://weca.st/noise-repellent/noise-repellent-m.js'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/noise-repellent/noise-repellent-m.js && \
    curl 'https://weca.st/noise-repellent/noise-repellent-m.asm.js'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/noise-repellent/noise-repellent-m.asm.js && \
    curl 'https://weca.st/noise-repellent/noise-repellent-m.wasm.js'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/noise-repellent/noise-repellent-m.wasm.js && \
    curl 'https://weca.st/noise-repellent/noise-repellent-m.wasm.wasm'   -H 'Referer: https://weca.st/awp/ennuicastr-worker.js?v=p' --compressed >/var/www/html/rec/noise-repellent/noise-repellent-m.wasm.wasm && \
    sed -i 's+3.6b.4+3.6.4+g' /var/www/html/rec/libav/*; \
# TODO -- generate and install paypal subscriptions OOB creation script doesn't work
#    cd /ennuicastr-server/subscription;
#    if [ ! -e /external/subscriptions.json ]; then 
#      node create.js >> /external/subscriptions.json.new;
#      echo -n '\"subscription\": \"'>/external/subscriptions.json && \
#      cat /external/subscriptions.json.new >> /external/subscriptions.json && \
#      echo '\"' >>/external/subscriptions.json; 
#    fi
"
docker-compose restart web
docker-compose up -d
#docker system prune -af

service nginx configtest && service nginx reload || echo Error loading nginx
