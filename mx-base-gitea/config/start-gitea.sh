#!/bin/bash
sleep 20
set -x
. shared_logging.sh
###############################

## ACtion - Update INST_LOCFILE & 
HOST_FQDN=`hostname -f`
INST_LOCFILE="${STEPPATH}/certs/root_ca.crt"
#MX_CONTAINER_NAME
CERT_LOCATION=${HOME}/cert
CERT_NAME="gitea"
DB_CERT_LOCATION=${HOME}/.postgresql
#Gitea needs the certname postgresql else it wont work
DB_CERT_NAME="postgresql"
GITEA_TOKENS_DIR=${HOME}/.tok

local_app=${MX_BASE_APP_DIR}
local_app_custom=${local_app}/custom
local_app_log=${local_app}/log

check_step_ca () {

        #check_step_ca ${number_of_loops} ${sleep duration}
        for (( i=1; i<=${1}; i++ )); do
                curl -sk  ${MX_STEP_HOST}/roots.pem -o stepCA.pem
                retVal=$?
                if [[ $retVal -eq 0 ]];then
                        let stepca_cdur=$(step ca provisioner list --ca-url=${MX_STEP_HOST} --root=./stepCA.pem |jq -r '.[0].claims.maxTLSCertDuration | split("h")[0]')
                        let app_cdur=$(echo $MX_GITEA_CERT_DUR |sed "s/h//")
                        if [[ "$app_cdur" -le "$stepca_cdur" ]]; then
                                return 0
                                else
                                logwarn "Step is available but the max certificate expiry is not set correctly, post script wants $app_cdur waiting for step as its currently $stepca_cdur: attempt $i / ${1}"
                        fi
                fi
                sleep ${2}
        done

        return 1

}

check_gitea () {

        count_default_checks=$(${MX_BASE_APP_DIR}/gitea -c ${local_app_custom}/app.ini doctor check --list | grep -c "^*")
        count_checks_passed=$(${MX_BASE_APP_DIR}/gitea -c ${local_app_custom}/app.ini doctor check | grep -c "OK")

        if [[ "$count_default_checks" -eq "$count_checks_passed" ]]; then
                loginfo "All default gitea checks passed with OK"

        else
                logerr "Some issues with gitea default checks, $count_checks_passed out of $count_default_checks passed"

        fi
}

renew_tokens () {

	gitea -c ${local_app_custom}/app.ini generate secret INTERNAL_TOKEN >${GITEA_TOKENS_DIR}/internal_token
        gitea -c ${local_app_custom}/app.ini generate secret JWT_SECRET >${GITEA_TOKENS_DIR}/jwt_secret
	gitea -c ${local_app_custom}/app.ini generate secret LFS_JWT_SECRET >${GITEA_TOKENS_DIR}/lfs_jwt_secret
	chmod 440 ${GITEA_TOKENS_DIR}/*

}



initialise_app () {

	loginfo "initial setup of application"
        FP=$(step certificate fingerprint stepCA.pem)
        step ca bootstrap --ca-url ${MX_STEP_HOST} --fingerprint ${FP}
        step ca certificate ${HOST_FQDN}  ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DUR} --san ${HOST_FQDN} --san ${MX_CONTAINER_NAME} --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
        cat ${CERT_LOCATION}/${CERT_NAME}.crt .step/certs/root_ca.crt  >> ${CERT_LOCATION}/giteafullchain.crt
        step ca certificate ${MX_POSTGRES_USER} ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DUR} --san ${MX_POSTGRES_USER} --san ${HOST_FQDN} --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
        cp -p ${STEPPATH}/certs/root_ca.crt ${DB_CERT_LOCATION}/root.crt

	renew_tokens
	


}

renew () {

	loginfo "checking certificate for renewal"
	step certificate verify ${CERT_LOCATION}/${CERT_NAME}.crt  --roots ${STEPPATH}/certs/root_ca.crt  --host=$CERT_HOST
        retVal=$?
        if [[ $retVal -eq 0 ]];then
		loginfo "renew gitea certificate"
                step ca renew -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                step ca renew -f ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key
        else
                logwarn "gitea certificate expired or other error "
                loginfo "recreate gitea certificate"
		rm -f ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key
                rm -r ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key 
                step ca certificate ${HOST_FQDN}  ${CERT_LOCATION}/${CERT_NAME}.crt ${CERT_LOCATION}/${CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DUR} --san ${HOST_FQDN} --san ${MX_CONTAINER_NAME} --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                step ca certificate ${MX_POSTGRES_USER} ${DB_CERT_LOCATION}/${DB_CERT_NAME}.crt ${DB_CERT_LOCATION}/${DB_CERT_NAME}.key  --not-after ${MX_GITEA_CERT_DUR} --san ${MX_POSTGRES_USER} --san ${HOST_FQDN} --provisioner-password-file  <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                cp -p ${STEPPATH}/certs/root_ca.crt ${DB_CERT_LOCATION}/root.crt
        fi

}

config_file () {

	loginfo "config_file setup"
        PPW="-"
        #special char password
        sed -i "s/ZGIT_DOMAIN/${MX_GIT_DOMAIN}/g;s/DB_HOST/${MX_DB_HOST}/g;s/DB_PORT/${MX_DB_PORT}/g;s/POSTGRES_PASSWORD/\`${PPW}\`/g;s/ZGIT_PORT/${MX_GIT_PORT}/g" ${local_app_custom}/app.ini
	sed -i "s#ZHOME#${HOME}#g;s#ZCERTNAME#${CERT_NAME}#g" ${local_app_custom}/app.ini

}


startup () {
        
	loginfo "startup"
	C=0
	while [ $C -lt 2 ];do
		if [[ "$(cat /mnt/shared/postgres_status)" == "up" ]]; then
			loginfo "database up, starting gitea"
			${MX_BASE_APP_DIR}/gitea -c ${local_app_custom}/app.ini > /proc/1/fd/1 2>/proc/1/fd/2 &

			break
		else
			loginfo "check ${C}/3 $db unavailable, waiting 10 seconds for db before starting gitea"
                        sleep 10
                        if [[ $C -eq 3 ]] ;then
                                logerr "database not available exiting without starting gitea"
                        fi

		fi
		let C++
	done
	sleep 2
}



post_startup_init () {

	loginfo "post start initialisation actions"

}

stopapp () {

	loginfo "stopping "
	${MX_BASE_APP_DIR}/gitea -c ${local_app_custom}/app.ini manager shutdown > /proc/1/fd/1 2>/proc/1/fd/2 &
        retVal=$?
        if [[ $retVal -eq 0 ]];then
                loginfo "gitea shutdown"
        else
                logerr "shutdown of gitea ended in error"
        fi


}


restart () {

        loginfo "restart"
        ${MX_BASE_APP_DIR}/gitea -c ${local_app_custom}/app.ini manager restart
        retVal=$?
        if [[ $retVal -eq 0 ]];then
                loginfo "gitea restarted"
        else
                logerr "restart of gitea ended in error"
        fi


}

shutdown_stopapp () {

	stopapp
	exit 0

}




andcheck () {

	loginfo "test"
	loginfo "sleeping and checking certificate expiry"
	while true
	do
		#step certificate needs-renewal --expires-in 2% ${CERT_LOCATION}/${CERT_NAME}.crt
		step certificate needs-renewal --expires-in ${MX_GITEA_EXP_CHECK} ${CERT_LOCATION}/${CERT_NAME}.crt
		retVal=$?
		if [[ $retVal -eq 0 ]];then
			renew
                        stopapp
			#pkill -P $$
			startup
		fi
		sleep 10m
                check_gitea
	done

}


trap shutdown_stopapp TERM INT

if [[ ! -f ${INST_LOCFILE} ]];then
        if check_step_ca 2 10; then
                loginfo "setup gitea"
                config_file
                initialise_app
                startup
                #post_startup_init
                andcheck
        else
                logerr "Exiting setup as step ca cant be contacted"
        fi


else
	loginfo "remove JWT if found in app.ini and move to dedicated location"
        sed -i "s#^LFS_JWT_SECRET.*#LFS_JWT_SECRET_URI = file:/home/gitea1/.tok/lfs_jwt_secret#" ${local_app_custom}/app.ini
 
        if check_step_ca 2 10; then
                loginfo "Renew certificate and startup gitea"
                renew
		renew_tokens
                startup
                andcheck
        else
                logerr "Failure to connect to step-ca - can't renew certificates but starting gitea and the current certificates may cause issues "
		renew_tokens
                startup
                andcheck      
        fi

fi



tail -f /dev/null

