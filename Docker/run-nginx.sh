#!/bin/bash

export CONTAINERROLE=":${CONTAINERROLE:-all}:"
export DEBIAN_FRONTEND=noninteractive
export DA_ROOT="${DA_ROOT:-/usr/share/docassemble}"
export DA_DEFAULT_LOCAL="local3.12"

export DA_ACTIVATE="${DA_PYTHON:-${DA_ROOT}/${DA_DEFAULT_LOCAL}}/bin/activate"
export DA_CONFIG_FILE="${DA_CONFIG:-${DA_ROOT}/config/config.yml}"
source /dev/stdin < <(su -c "source \"$DA_ACTIVATE\" && python -m docassemble.base.read_config \"$DA_CONFIG_FILE\"" www-data | grep -e '^export LOCALE=' -e '^export DAHOSTNAME=' -e '^export EC2=' -e '^export BEHINDHTTPSLOADBALANCER=' -e '^export USELETSENCRYPT=' -e '^export DALOCATIONREWRITE=' -e '^export WSGIROOT=' -e '^export POSTURLROOT=' -e '^export DAMAXCONTENTLENGTH=' -e '^export DASSLPROTOCOLS=' -e '^export DASSLCIPHERS=' -e '^export DAWEBSOCKETSIP=' -e '^export DAWEBSOCKETSPORT=' -e '^export PORT=' -e '^export USEHTTPS=' -e '^export DAREADONLYFILESYSTEM=')

set -- $LOCALE
export LANG=$1

if [ "${DAHOSTNAME:-none}" == "none" ]; then
    if [ "${EC2:-false}" == "true" ]; then
	export LOCAL_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/local-hostname`
	export PUBLIC_HOSTNAME=`curl -s http://169.254.169.254/latest/meta-data/public-hostname`
    else
	export LOCAL_HOSTNAME=`hostname --fqdn`
	export PUBLIC_HOSTNAME="${LOCAL_HOSTNAME}"
    fi
    export DAHOSTNAME="${PUBLIC_HOSTNAME}"
fi

if [ "${DAREADONLYFILESYSTEM:-false}" == "false" ]; then
    if [ "${BEHINDHTTPSLOADBALANCER:-false}" == "true" ] && [[ $CONTAINERROLE =~ .*:(all|web):.* ]]; then
	DAREALIP="include ${DA_ROOT}/config/nginx-realip;"
	ln -sf /etc/nginx/sites-available/docassembleredirect /etc/nginx/sites-enabled/docassembleredirect
    else
	DAREALIP=""
	rm -f /etc/nginx/sites-enabled/docassembleredirect
    fi

    if [ "${USELETSENCRYPT:-false}" == "true" ] && [ -f "/etc/letsencrypt/live/${DAHOSTNAME}/fullchain.pem" ]; then
	DASSLCERTIFICATE="/etc/letsencrypt/live/${DAHOSTNAME}/fullchain.pem; # managed by Certbot"
	DASSLCERTIFICATEKEY="/etc/letsencrypt/live/${DAHOSTNAME}/privkey.pem; # managed by Certbot"
    else
	DASSLCERTIFICATE="/etc/ssl/docassemble/nginx.crt;"
	DASSLCERTIFICATEKEY="/etc/ssl/docassemble/nginx.key;"
    fi

    DASSLPROTOCOLS=${DASSLPROTOCOLS:-TLSv1.2 TLSv1.3}
    DASSLCIPHERS=${DASSLCIPHERS:-HIGH:!aNULL:!MD5}

    if [ "${POSTURLROOT}" == "/" ]; then
	DALOCATIONREWRITE=" "
    else
	DALOCATIONREWRITE="location = ${WSGIROOT} { rewrite ^ ${POSTURLROOT}; }"
    fi

    sed -e 's@{{DAHOSTNAME}}@'"${DAHOSTNAME:-localhost}"'@' \
    -e 's@{{DALOCATIONREWRITE}}@'"${DALOCATIONREWRITE}"'@' \
    -e 's@{{DAWSGIROOT}}@'"${WSGIROOT}"'@' \
    -e 's@{{DAPOSTURLROOT}}@'"${POSTURLROOT}"'@' \
    -e 's@{{DAREALIP}}@'"${DAREALIP}"'@' \
    -e 's@{{DAMAXCONTENTLENGTH}}@'"${DAMAXCONTENTLENGTH}"'@' \
    -e 's@{{DASSLCERTIFICATE}}@'"${DASSLCERTIFICATE}"'@' \
    -e 's@{{DASSLCERTIFICATEKEY}}@'"${DASSLCERTIFICATEKEY}"'@' \
    -e 's@{{DASSLPROTOCOLS}}@'"${DASSLPROTOCOLS}"'@' \
    -e 's@{{DASSLCIPHERS}}@'"${DASSLCIPHERS}"'@' \
    -e 's@{{DAWEBSOCKETSIP}}@'"${DAWEBSOCKETSIP:-127.0.0.1}"'@' \
    -e 's@{{DAWEBSOCKETSPORT}}@'"${DAWEBSOCKETSPORT:-5000}"'@' \
    -e 's@{{DALISTENPORT}}@'"${PORT:-80}"'@' \
    "${DA_ROOT}/config/nginx-ssl.dist" > "/etc/nginx/sites-available/docassemblessl"

    sed -e 's@{{DAHOSTNAME}}@'"${DAHOSTNAME:-localhost}"'@' \
    -e 's@{{DALOCATIONREWRITE}}@'"${DALOCATIONREWRITE}"'@' \
    -e 's@{{DAWSGIROOT}}@'"${WSGIROOT}"'@' \
    -e 's@{{DAPOSTURLROOT}}@'"${POSTURLROOT}"'@' \
    -e 's@{{DAREALIP}}@'"${DAREALIP}"'@' \
    -e 's@{{DAMAXCONTENTLENGTH}}@'"${DAMAXCONTENTLENGTH}"'@' \
    -e 's@{{DAWEBSOCKETSIP}}@'"${DAWEBSOCKETSIP:-127.0.0.1}"'@' \
    -e 's@{{DAWEBSOCKETSPORT}}@'"${DAWEBSOCKETSPORT:-5000}"'@' \
    -e 's@{{DALISTENPORT}}@'"${PORT:-80}"'@' \
    "${DA_ROOT}/config/nginx-http.dist" > "/etc/nginx/sites-available/docassemblehttp"

    sed -e 's@{{DAHOSTNAME}}@'"${DAHOSTNAME:-localhost}"'@' \
    -e 's@{{DAMAXCONTENTLENGTH}}@'"${DAMAXCONTENTLENGTH}"'@' \
    "${DA_ROOT}/config/nginx-log.dist" > "/etc/nginx/sites-available/docassemblelog"

    sed -e 's@{{DAHOSTNAME}}@'"${DAHOSTNAME:-localhost}"'@' \
	-e 's@{{DALISTENPORT}}@'"${PORT:-80}"'@' \
    "${DA_ROOT}/config/nginx-redirect.dist" > "/etc/nginx/sites-available/docassembleredirect"

    sed -e 's@{{DAHOSTNAME}}@'"${DAHOSTNAME:-localhost}"'@' \
	-e 's@{{DALISTENPORT}}@'"${PORT:-80}"'@' \
	"${DA_ROOT}/config/nginx-ssl-redirect.dist" > "/etc/nginx/sites-available/docassemblesslredirect"
fi

if [[ $CONTAINERROLE =~ .*:(log):.* ]]; then
    if [ "${DAREADONLYFILESYSTEM:-false}" == "false" ]; then
	ln -sf /etc/nginx/sites-available/docassemblelog /etc/nginx/sites-enabled/docassemblelog
    fi
    su -c "source \"$DA_ACTIVATE\" && uwsgi --ini \"${DA_ROOT}/config/docassemblelog.ini\"" www-data &
else
    if [ "${DAREADONLYFILESYSTEM:-false}" == "false" ]; then
	rm -f /etc/nginx/sites-enabled/docassemblelog
    fi
fi

if [ "${DAREADONLYFILESYSTEM:-false}" == "false" ]; then
    if [[ $CONTAINERROLE =~ .*:(all|web):.* ]]; then
	if [ "${USEHTTPS:-false}" == "true" ]; then
	    rm -f /etc/nginx/sites-enabled/docassemblehttp
	    ln -sf /etc/nginx/sites-available/docassemblessl /etc/nginx/sites-enabled/docassemblessl
	    ln -sf /etc/nginx/sites-available/docassemblesslredirect /etc/nginx/sites-enabled/docassemblesslredirect
	else
	    rm -f /etc/nginx/sites-enabled/docassemblessl
	    rm -f /etc/nginx/sites-enabled/docassemblesslredirect
	    ln -sf /etc/nginx/sites-available/docassemblehttp /etc/nginx/sites-enabled/docassemblehttp
	    rm -f /etc/letsencrypt/da_using_lets_encrypt
	fi
    else
	rm -f /etc/nginx/sites-enabled/docassemblehttp
	rm -f /etc/nginx/sites-enabled/docassemblessl
	rm -f /etc/nginx/sites-enabled/docassemblesslredirect
	rm -f /etc/letsencrypt/da_using_lets_encrypt
    fi
fi

function stopfunc {
    if [[ $CONTAINERROLE =~ .*:(log):.* ]] && [ -f /var/run/uwsgi/uwsgilog.pid ]; then
	UWSGILOG_PID=$(</var/run/uwsgi/uwsgilog.pid)
	if [ $? -eq 0 ]; then
	    echo "Sending stop command to uwsgi log" >&2
	    kill -INT $UWSGILOG_PID
	    echo "Waiting for uwsgi log to stop" >&2
	    wait $UWSGILOG_PID
	    echo "uwsgi log stopped" >&2
	fi
    fi
    if [ -f /var/run/nginx.pid ]; then
	NGINX_PID=$(</var/run/nginx.pid)
	if [ $? -eq 0 ]; then
	    echo "Sending stop command" >&2
	    kill -QUIT $NGINX_PID
	    echo "Waiting for nginx to stop" >&2
	    wait $NGINX_PID
	    echo "nginx stopped" >&2
	fi
    fi
    exit 0
}

trap stopfunc SIGINT SIGTERM

/usr/sbin/nginx -g "daemon off;" &
wait %1
