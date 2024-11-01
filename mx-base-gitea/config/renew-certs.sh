#!/bin/bash

. shared_logging.sh


## ACtion - Update INST_LOCFILE &
HOST_FQDN=`hostname -f`
INST_LOCFILE="${STEPPATH}/certs/root_ca.crt"
#MX_CONTAINER_NAME
CERT_LOCATION=${HOME}/cert
CERT_NAME="gitea"
DB_CERT_LOCATION=${HOME}/.postgresql
DB_CERT_NAME="postgresdb"
GITEA_TOKENS_DIR=${HOME}/.tok

local_app=${MX_BASE_APP_DIR}
local_app_custom=${local_app}/custom
local_app_log=${local_app}/log


renew_certs () {

        loginfo "checking certificate for renewal"
        step certificate verify ${CERT_LOCATION}/${CERT_NAME}.crt  --roots ${STEPPATH}/certs/root_ca.crt  --host=$CERT_HOST
        retVal=$?
        if [ $retVal -eq 0 ];then
                loginfo "renew gitea certificate"
                step ca renew -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                step ca renew -f ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key
        else
                logwarn "gitea certificate expired or other error "
                loginfo "recreate gitea certificate"
                rm -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                rm -r ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key
         #      step ca certificate $DB_USER ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DURT_DUR} --san $CERT_HOST  --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                step ca certificate ${HOST_FQDN}  ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DUR} --san ${HOST_FQDN} --san ${MX_CONTAINER_NAME} --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                step ca certificate ${MX_POSTGRES_USER} ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DUR} --san ${MX_POSTGRES_USER} --san ${HOST_FQDN} --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                cp -p ${STEPPATH}/certs/root_ca.crt ${DB_CERT_LOCATION}/root.crt
        fi

}


renew_tokens () {

        gitea -c ${local_app_custom}/app.ini generate secret INTERNAL_TOKEN >${GITEA_TOKENS_DIR}/internal_token
        gitea -c ${local_app_custom}/app.ini generate secret JWT_SECRET >${GITEA_TOKENS_DIR}/jwt_secret
        gitea -c ${local_app_custom}/app.ini generate secret LFS_JWT_SECRET >${GITEA_TOKENS_DIR}/lfs_jwt_secret

}

case $1 in
	certs)
		renew_certs
		;;
	tokens)
		renew_tokens
		;;
	both)
		renew_certs
		renew_tokens
		;;
	*)
		logerr "incorrect option, only certs, tokens or both supported as passed paratemr"
		;;

esac

