#!/bin/bash
#set -e
#Script to setup kerberos in one click! :)
#Author - Kuldeep Kulkarni (http://crazyadmins.com)
#############
#AMBARI_VERSION=`rpm -qa|grep 'ambari-server-'|head -1|cut -d'-' -f3`

source $LOC/ambcli.sh
AMBARI_VERSION="$(ambget services/AMBARI/components/AMBARI_SERVER?fields=RootServiceComponents/component_version | jq -r '.RootServiceComponents| select (.component_name=="AMBARI_SERVER")|.component_version')"
export AMBARI_VERSION ; echo AMBARI_VERSION=$AMBARI_VERSION
[[ -z $KERBEROS_CLIENTS ]] && KERBEROS_CLIENTS=$(ambgets hosts |  jq -r '[.items[].Hosts.host_name]|join (", ")')
echo "KERBEROS CLIENTS WILL BE INSTALLED ON $KERBEROS_CLIENTS"

setup_kdc()
{

	echo -e "\n`ts` Installing kerberos RPMs"
	yum -y install krb5-server krb5-libs krb5-workstation
	echo -e "\n`ts` Configuring Kerberos"
	sed -i.bak "s/EXAMPLE.COM/$REALM/g" $LOC/krb5.conf.default
	sed -i.bak "s/kerberos.example.com/$KDC_HOST/g" $LOC/krb5.conf.default
	cat $LOC/krb5.conf.default > /etc/krb5.conf
	kdb5_util create -s -P $KDC_ADMIN_PASS
	echo -e "\n`ts` Starting KDC services"
	service krb5kdc start
	service kadmin start
	chkconfig krb5kdc on
	chkconfig kadmin on
	echo -e "\n`ts` Creating admin principal"
	kadmin.local -q "addprinc -pw $KDC_ADMIN_PASS $KDC_ADMIN"
	sed -i.bak "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kadm5.acl
	echo -e "\n`ts` Restarting kadmin"
	service kadmin restart
	
}

create_payload()
{
	# First arguemtn i.e. $1 = service|credentails
	if [ "$1" == "service" ]
	then

		echo "[
  {
    \"Clusters\": {
      \"desired_config\": {
        \"type\": \"krb5-conf\",
        \"tag\": \"version1\",
        \"properties\": {
          \"domains\":\"'$DOMAINS'\",
          \"manage_krb5_conf\": \"true\",
          \"conf_dir\":\"/etc\",
	  \"content\" : \"$(sed ':a;N;$!ba;s/\n/\\n/g' $KDC_TYPE)\"
        }
      }
    }
  },
  {
    \"Clusters\": {
      \"desired_config\": {
        \"type\": \"kerberos-env\",
        \"tag\": \"version1\",
        \"properties\": {
          \"kdc_type\": \"$KDC_TYPE\",
          \"manage_identities\": \"true\",
          \"install_packages\": \"true\",
          \"encryption_types\": \"aes des3-cbc-sha1 rc4 des-cbc-md5\",
          \"realm\" : \"$REALM\",
          \"kdc_hosts\" : \"$KDC_HOST\",
          \"kdc_host\" : \"$KDC_HOST\",
          \"admin_server_host\" : \"$KDC_HOST\",
          \"executable_search_paths\" : \"/usr/bin, /usr/kerberos/bin, /usr/sbin, /usr/lib/mit/bin, /usr/lib/mit/sbin\",
          \"password_length\": \"20\",
          \"password_min_lowercase_letters\": \"1\",
          \"password_min_uppercase_letters\": \"1\",
          \"password_min_digits\": \"1\",
          \"password_min_punctuation\": \"1\",
          \"password_min_whitespace\": \"0\",
          \"service_check_principal_name\" : \"${cluster_name}-${short_date}\",
          \"case_insensitive_username_rules\" : \"false\"
        }
      }
    }
  }
]" | tee $LOC/payload

	elif [ "$1" == credentials ]
	then
		echo "{
  \"session_attributes\" : {
    \"kerberos_admin\" : {
      \"principal\" : \"${KDC_ADMIN}@${REALM}\",
      \"password\" : \"$KDC_ADMIN_PASS\"
    }
  },
  \"Clusters\": {
    \"security_type\" : \"KERBEROS\"
  }
}" | tee $LOC/payload
	fi
  cat $LOC/payload >> rest.log
}

conf_krb_service() {
	#Todo: check current cluster state (has configus/kerberos enabled/ etc..)
	echo -e "\n`ts` Adding KERBEROS Service to cluster"
	ambsrv add KERBEROS
	echo -e "\n`ts` Adding KERBEROS_CLIENT component to the KERBEROS service"
	$sleep 1
	ambpost clusters/$CLUSTER_NAME/services/KERBEROS/components/KERBEROS_CLIENT
	create_payload service
	$sleep 1
	ambput clusters/$CLUSTER_NAME  "@$LOC"/payload  

}

conf_krb_clients() {
	echo -e "\n `ts` Creating the KERBEROS_CLIENT host components for each host"
	for client in `echo $KERBEROS_CLIENTS|tr ',' ' '`;
	do
	  ambpost clusters/$CLUSTER_NAME/hosts?Hosts/host_name=$client '{"host_components" : [{"HostRoles" : {"component_name":"KERBEROS_CLIENT"}}]}'
	  $sleep 1
	done
}

install_kerberos() {
	echo -e "\n`ts` Installing the KERBEROS service and components"
	ambput clusters/$CLUSTER_NAME/services/KERBEROS '{"ServiceInfo": {"state" : "INSTALLED"}}'
	echo -e "\n`ts` Sleeping for 1 minute"
	$sleep 60

}

create_krb_cred() {
	if [[ "${AMBARI_VERSION:0:3}" > "2.7" ]] || [[ "${AMBARI_VERSION:0:3}" == "2.7" ]]
        then
                echo -e "\n`ts` Uploading Kerberos Credentials"
                ambpost clusters/${CLUSTER_NAME}/credentials/kdc.admin.credential '{ "Credential" : { "principal" : "'$KDC_ADMIN'@'$REALM'", "key" : "'$KDC_ADMIN_PASS'", "type" : "temporary" }}' 
                $sleep 1
        else
			echo -e "\n`ts` Ambari post 2.7 version does not allow saving credentials"
	fi

}

enable_kerberos(){

  amb srv stop all
  echo -e "\n`ts` Enabling Kerberos"
  create_payload credentials
  ambput clusters/$CLUSTER_NAME @$LOC/payload
  amb srv start all

}
configure_kerberos()
{
  conf_krb_service
  conf_krb_clients
  install_kerberos
  create_krb_cred
  enable_kerberos
}

[[ ! -z $SETUPKDC ]] && setup_kdc|tee -a $LOC/Kerb_setup.log
[[ ! -z $KERBERIZE ]] && configure_kerberos|tee -a $LOC/Kerb_setup.log
