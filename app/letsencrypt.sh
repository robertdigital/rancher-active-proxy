#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

seconds_to_wait=3600
ACME_CA_URI="${ACME_CA_URI:-https://acme-v01.api.letsencrypt.org/directory}"
ACME_CA_URI_STAGING="https"

source /app/functions.sh

create_link() {
    local readonly target=${1?missing target argument}
    local readonly source=${2?missing source argument}
    [[ -f "$target" ]] && return 1
    ln -sf "$source" "$target"
}

create_links() {
    local readonly base_domain=${1?missing base_domain argument}
    local readonly domain=${2?missing base_domain argument}

    if [[ ! -f "/etc/nginx/certs/$base_domain"/fullchain.pem || \
          ! -f "/etc/nginx/certs/$base_domain"/key.pem ]]; then
        return 1
    fi
    local return_code=1
    create_link "/etc/nginx/certs/$domain".crt "./$base_domain"/fullchain.pem
    return_code=$(( $return_code & $? ))
    create_link "/etc/nginx/certs/$domain".key "./$base_domain"/key.pem
    return_code=$(( $return_code & $? ))
    if [[ -f "/etc/nginx/certs/dhparam.pem" ]]; then
        create_link "/etc/nginx/certs/$domain".dhparam.pem ./dhparam.pem
        return_code=$(( $return_code & $? ))
    fi
    return $return_code
}


update_certs() {
	echo "Beginning !!"
    [[ ! -f /app/letsencrypt.conf ]] && return
	echo "OK ?"

    # Load relevant container settings
    unset LETSENCRYPT_CONTAINERS
    source /app/letsencrypt.conf

    for cid in "${LETSENCRYPT_CONTAINERS[@]}"; do

	# Derive host and email variable names
        host_varname="LETSENCRYPT_${cid}_HOST"

        # Array variable indirection hack: http://stackoverflow.com/a/25880676/350221
        hosts_array=$host_varname[@]
        email_varname="LETSENCRYPT_${cid}_EMAIL"
        test_certificate_varname="LETSENCRYPT_${cid}_TEST"

        create_test_certificate=false

        if [[ $(lc "${!test_certificate_varname:-}") == true ]]; then
            create_test_certificate=true
        fi

        params_d_str=""
        [[ $DEBUG == true ]] && params_d_str+=" -v"

        hosts_array_expanded=("${!hosts_array}")
	echo "$host_array_expanded"
        # First domain will be our base domain
        base_domain="${hosts_array_expanded[0]}"

        if [[ "$create_test_certificate" == true ]]; then
            # Use staging acme end point
            acme_ca_uri="https://acme-staging.api.letsencrypt.org/directory"
            if [[ ! -f /etc/nginx/certs/.${base_domain}.test ]]; then
                # Remove old certificates
                rm -rf /etc/nginx/certs/${base_domain}
                for domain in "${!hosts_array}"; do
                    rm -f /etc/nginx/certs/$domain.{crt,key,dhparam.pem}
                done
                touch /etc/nginx/certs/.${base_domain}.test
            fi
        else
            acme_ca_uri="$ACME_CA_URI"
            if [[ -f /etc/nginx/certs/.${base_domain}.test ]]; then
                # Remove old test certificates
                rm -rf /etc/nginx/certs/${base_domain}
                for domain in "${!hosts_array}"; do
                    rm -f /etc/nginx/certs/$domain.{crt,key,dhparam.pem}
                done
                rm -f /etc/nginx/certs/.${base_domain}.test
            fi
        fi

        # Create directory for the first domain
        mkdir -p /etc/nginx/certs/$base_domain
        cd /etc/nginx/certs/$base_domain

        for domain in "${!hosts_array}"; do
            # Add all the domains to certificate
            params_d_str+=" -d $domain"
            # Add location configuration for the domain
            add_location_configuration "$domain" || reload_nginx
        done

        echo "Creating/renewal $base_domain certificates... (${hosts_array_expanded[*]})"

	echo "## AJOUTER CERTBOT ##"      

    done

    nginx -t && nginx -s reload
}

update_certs

