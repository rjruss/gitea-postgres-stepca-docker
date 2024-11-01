#!/bin/bash

set -x
. shared_logging.sh

HOST_FQDN=`hostname -f`

INST_LOCFILE="/home/step/.step/authorities/${MX_AUTH_NAME}/config/ca.json"

initialise_step () {

		loginfo "initialise step"
                step ca init   --deployment-type=standalone --provisioner="${MX_PROV_NAME}"  --name="${MX_STEP_NAME}" --context="${MX_CONT_NAME}" --authority="${MX_AUTH_NAME}" --dns=localhost --dns=${HOST_FQDN} --dns=${MX_CONTAINER_NAME} --address="${MX_ADDRESS}" --remote-management=${MX_REMOT_MAN} --password-file <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)

}

renew () {
		loginfo "renew"

}

config_file () {
		loginfo "config_file"

}


startup () {

		loginfo "startup step"
		step-ca   --password-file <(set +x;echo -n `shared_get_info.sh STEP PW`;set -x) > /proc/1/fd/1 2>/proc/1/fd/2  &
		sleep 10

}


post_startup_init () {

		loginfo "post initialisation steps add a superstep user and provisioner"
                #Some changes made that these commands now fail in step due to "no admin cred.. found" but still adds the superstep account -
                step ca admin add superstep "${MX_PROV_NAME}" --admin-subject=step --admin-password-file=<(set +x;echo -n `shared_get_info.sh STEP PW`;set -x) --super
                step ca admin remove step  --admin-subject=superstep --admin-password-file=<(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                step ca admin list  --admin-subject=superstep --admin-password-file=<(set +x;echo -n `shared_get_info.sh STEP PW`;set -x)
                step ca provisioner update "${MX_PROV_NAME}"  --x509-max-dur=${MX_CERT_MAX_DUR} --admin-password-file=<(set +x;echo -n `shared_get_info.sh STEP PW`;set -x) --admin-subject=superstep

                loginfo "STEP VERSION INFO: $(step --version | paste -d " " - - )"
                loginfo "setup of step-ca completed"

}


check_step () {

                loginfo " health check "; 
}


andcheck () {

	loginfo "sleeping and checking step ca health output on loop"
        while true
        do
                step ca health
                retVal=$?
                if [ $retVal -eq 0 ];then
                        loginfo "step ca health check returned ok"
                        loginfo "step ca health check returned ok" > /proc/1/fd/1 2>/proc/1/fd/2  &
		else
			logerr "step ca health check is negative"
			logerr "step ca health check is negative" > /proc/1/fd/1 2>/proc/1/fd/2  &
                fi
        sleep 30m
        done


}

shared_get_info.sh STEP PW &>/dev/null
retVal=$?
if [[ $retVal -eq 0 ]];then
        if [ ! -f ${INST_LOCFILE} ];then
                loginfo "setup step-ca"
                initialise_step
        #        config_file
                startup
		post_startup_init
         #       sleep 25
                andcheck

        else
        #        renew
                startup
                andcheck
        fi
else
        logerr "ERROR: cant access security info from age process - step-ca is not setup"
fi

#catch all infinite loop
tail -f /dev/null

