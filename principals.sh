#!/bin/sh
if [ -z $REALM ]; then
    if [ -z $KRB5_CONFIG ]; then
	KRB5_CONFIG=/etc/krb5.conf
    fi
    REALM=`grep default_realm $KRB5_CONFIG | awk '{print $3}'`
fi

if [ -z $REALM ]; then
    echo "could not figure out your default Kerberos realm: check your /etc/krb5.conf file."
    exit 1
fi


if [ -z $HOSTNAME ]; then
    HOSTNAME=`hostname -f`
fi
echo "using hostname: $HOSTNAME for 'instance' component of"
echo "   server principals (service/$HOSTNAME@$REALM)."

KADMIN_LOCAL="sudo kadmin.local"
KDC_START="sudo service krb5kdc restart"
NORMAL_USER=`whoami`

# This script is idempotent: running it multiple times results in the same state.
# as if you only ran it once. (Although the generated keytab contents will differ 
# each time).
# Currently accomplished by deleting existing
# principles and keytabs, if any, and then (re-)creating.
SERVICE_KEYTAB=services.keytab
rm -f `pwd`/$SERVICE_KEYTAB
#1. services

#TODO: delete existing principals other than krbtgt/$REALM; otherwise
#the KDC database will get cluttered with old X/$HOSTNAME principals if the 
#host's hostname changes frequently (as happens with EC2 instances).
#
#1.0. krbtgt principal: all other principals' maxrenewlife must
#     be less than or equal to krbtgt's maxrenewlife, so set it first.
echo "modprinc -maxrenewlife 7days krbtgt/$REALM" | $KADMIN_LOCAL

#1.1. host
echo "delprinc -force host/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "addprinc -randkey host/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "ktadd -k `pwd`/$SERVICE_KEYTAB host/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days host/$HOSTNAME@$REALM" | $KADMIN_LOCAL

#1.2. zookeeper
echo "delprinc -force zookeeper/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "addprinc -randkey zookeeper/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "ktadd -k `pwd`/$SERVICE_KEYTAB zookeeper/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days zookeeper/$HOSTNAME@$REALM" | $KADMIN_LOCAL

#1.3. hdfs
echo "delprinc -force hdfs/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "addprinc -randkey hdfs/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "ktadd -k `pwd`/$SERVICE_KEYTAB hdfs/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days hdfs/$HOSTNAME@$REALM" | $KADMIN_LOCAL

#1.4. mapred
echo "delprinc -force mapred/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "addprinc -randkey mapred/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "ktadd -k `pwd`/$SERVICE_KEYTAB mapred/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days mapred/$HOSTNAME@$REALM" | $KADMIN_LOCAL

#1.4.5 historymanager
echo "delprinc -force jt/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "addprinc -randkey jt/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "ktadd -k `pwd`/$SERVICE_KEYTAB jt/$HOSTNAME@$REALM" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days jt/$HOSTNAME@$REALM" | $KADMIN_LOCAL


#1.5. yarn
echo "delprinc -force yarn/$HOSTNAME" | $KADMIN_LOCAL
echo "addprinc -randkey yarn/$HOSTNAME" | $KADMIN_LOCAL
echo "ktadd -k `pwd`/$SERVICE_KEYTAB yarn/$HOSTNAME" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days yarn/$HOSTNAME@$REALM" | $KADMIN_LOCAL

sudo chown $NORMAL_USER `pwd`/$SERVICE_KEYTAB

#2. users
echo
PASSWORD1="null1"
PASSWORD2="null2"
while [ $PASSWORD1 != $PASSWORD2 ]; do

    echo -n "Choose password for principal $NORMAL_USER: "
    stty -echo
    read PASSWORD1
    echo
    echo -n "Repeat password for principal $NORMAL_USER: "
    stty -echo
    read PASSWORD2

    echo
    if [ $PASSWORD1 != $PASSWORD2 ]; then
       echo "passwords did not match: please try again."
    fi

done
stty echo

PASSWORD=$PASSWORD1

echo "delprinc -force `whoami`@$REALM" | $KADMIN_LOCAL
echo "addprinc -pw $PASSWORD `whoami`@$REALM" | $KADMIN_LOCAL
echo "modprinc -maxrenewlife 7days `whoami`@$REALM" | $KADMIN_LOCAL

# only uncomment this if you want to use keytabs with client (rather
# than password).
#rm -f `pwd`/`whoami`.keytab
#echo "ktadd -k `pwd`/`whoami`.keytab `whoami`/@$REALM" | $KADMIN_LOCAL
#sudo chown $NORMAL_USER `pwd`/`whoami`.keytab


#Restart KDC (or start it if it's not running yet). 
#(Note that we could have done this earlier, but
# nothing until here requires the KDC to be running,
# It's more clear to put it here because it makes clear
# what the KDC is used for - (granting ticket-granting
# tickets, which we do next).
$KDC_START

echo "Now we will obtain a ticket-granting ticket and put it in your ticket cache. You should be asked for a password. Type the password you just chose in the last step."
kinit
if [ $? = '0' ]; then
    echo -n "Obtained and cached ticket successfully. Now attempting to renew your ticket.."
    kinit -R
    if [ $? = '0' ]; then
	echo "ok."
    else
	echo
	echo "failed to renew ticket. You may need use kadmin.local to modify your Kerberos policies to fix this."
    fi
else
    echo "Failed to obtain ticket. Try running kinit manually, being sure that you're entering your password correctly."
fi


