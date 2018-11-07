#!/bin/bash
#set -e
#Script to setup kerberos in one click! :)
#Author - Kuldeep Kulkarni (http://crazyadmins.com)
#############

LOC=`pwd`
PROP=ambari.props
source $LOC/$PROP
source $LOC/ambcli.sh
AMBARI_VERSION="$(ambget services/AMBARI/components/AMBARI_SERVER?fields=RootServiceComponents/component_version | jq -r '.RootServiceComponents| select (.component_name=="AMBARI_SERVER")|.component_version')"
export AMBARI_VERSION ; echo $AMBARI_VERSION
KDC_TYPE="ipa"
CURLOPTS='-s'
#sleep="echo -> "
sleep="sleep "
#############

setup_kdc()
{

	echo -e "\n`ts` Installing kerberos RPMs"
	yum -y install krb5-server krb5-libs krb5-workstation
	echo -e "\n`ts` Configuring Kerberos"
	sed -i.bak "s/EXAMPLE.COM/$REALM/g" $LOC/krb5.conf.default
	sed -i.bak "s/kerberos.example.com/$KDC_HOST/g" $LOC/krb5.conf.default
	cat $LOC/krb5.conf.default > /etc/krb5.conf
	kdb5_util create -s -P hadoop
	echo -e "\n`ts` Starting KDC services"
	service krb5kdc start
	service kadmin start
	chkconfig krb5kdc on
	chkconfig kadmin on
	echo -e "\n`ts` Creating admin principal"
	kadmin.local -q "addprinc -pw hadoop admin/admin"
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
        \"tag\": \"version10\",
        \"properties\": {
          \"domains\":\"\",
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
      \"principal\" : \"$KDC_ADMIN\",
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

configure_kerberos()
{
	echo -e "\n`ts` Enabling Kerberos"
	create_payload credentials
	ambput clusters/$CLUSTER_NAME @$LOC/payload 
	echo -e "\n`ts` Starting all services after 2 minutes..Please be patient :)"
	$sleep 120
	#ambput clusters/$CLUSTER_NAME/services  '{"ServiceInfo": {"state" : "STARTED"}}' 
	#echo -e "\n`ts` Please check Ambari UI\nThank You! :)"
}

[[ ! -z $SETUPKDC ]] && setup_kdc|tee -a $LOC/Kerb_setup.log
[[ ! -z $KERBERIZE ]] && configure_kerberos|tee -a $LOC/Kerb_setup.log
