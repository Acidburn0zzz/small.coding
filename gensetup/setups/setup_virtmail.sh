#!/bin/sh

# - CONFFILE (path to the configuration file)
# - STEPS (list of steps supported by the script)
# - STEPFROM (step to start from - can be empty)
# - STEPTO (step to go to - can be empty)
# - LOG (log file to use - will always be appended)
# - FAILED (temporary file; as long as it exists, the system did not fail)
# 
# Next, run the following functions:
# initTools;
#
# If you ever want to finish using the libraries, but want to keep the
# script alive, use cleanupTools;
##
## Helper commands
##

typeset CONFFILE=$1;
export CONFFILE;

typeset STEPS="installpostfix startpostfix installcourier startcourier installsasl startsasl certificates updatepostfix restartpostfix vmail installmysql startmysql loadsql installapache setupapache phpmyadmin mysqlauth restartauth mysqlpostfix restartpostfix2 squirrelmail";
export STEPS;

typeset STEPFROM=$2;
export STEPFROM;

typeset STEPTO=$3;
export STEPTO;

typeset LOG=/tmp/build.log;
export LOG;

typeset FAILED=$(mktemp);
export FAILED;

[ -f master.lib.sh ] && source ./master.lib.sh;

initTools;


##
## Functions
##

installpostfix() {
  logMessage "  > Installing 'postfix'... ";
  installSoftware -u postfix || die "Failed to install Postfix (emerge failed)";
  logMessage "done\n";

  logMessage "  > Updating main.cf... ";
  updateEqualNoQuotConfFile postfix.1.main /etc/postfix/main.cf;
  logMessage "done\n";

  logMessage "  > Updating master.cf... ";
  typeset FILE=/etc/postfix/master.cf;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e 's:smtpd$:smtpd -v:g' ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";
}

startpostfix() {
  logMessage "  > Need to start postfix!\n";
  die "Start postfix init script (/etc/init.d/postfix start) and continue with step \"installcourier\"";
}

installcourier() {
  logMessage "  > Installing 'courier-imap' and 'courier-authlib'... ";
  installSoftware -u courier-imap courier-authlib || die "Failed to install Courier software (emerge failed)";
  logMessage "done\n";

  logMessage "  > Updating pop3.cnf... ";
  typeset FILE=/etc/courier-imap/pop3d.cnf;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e "s:^C ?=.*:C=$(getValue courier.ssl.C):g" ${FILE};
  sed -i -e "s:^ST ?=.*:ST=$(getValue courier.ssl.ST):g" ${FILE};
  sed -i -e "s:^L ?=.*:L=$(getValue courier.ssl.L):g" ${FILE};
  sed -i -e "s:^O ?=.*:O=$(getValue courier.ssl.O):g" ${FILE};
  sed -i -e "s:^OU ?=.*:OU=$(getValue courier.ssl.OU):g" ${FILE};
  sed -i -e "s:^CN ?=.*:CN=$(getValue courier.ssl.CN):g" ${FILE};
  sed -i -e "s:^emailAddress ?=.*:emailAddress=$(getValue courier.ssl.emailAddress):g" ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Updating imapd.cnf... ";
  typeset FILE=/etc/courier-imap/imapd.cnf;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e "s:^C ?=.*:C=$(getValue courier.ssl.C):g" ${FILE};
  sed -i -e "s:^ST ?=.*:ST=$(getValue courier.ssl.ST):g" ${FILE};
  sed -i -e "s:^L ?=.*:L=$(getValue courier.ssl.L):g" ${FILE};
  sed -i -e "s:^O ?=.*:O=$(getValue courier.ssl.O):g" ${FILE};
  sed -i -e "s:^OU ?=.*:OU=$(getValue courier.ssl.OU):g" ${FILE};
  sed -i -e "s:^CN ?=.*:CN=$(getValue courier.ssl.CN):g" ${FILE};
  sed -i -e "s:^emailAddress ?=.*:emailAddress=$(getValue courier.ssl.emailAddress):g" ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Running mkpop3dcert... ";
  mkpop3dcert;
  if [ $? -ne 0 ] && [ ! -f /etc/courier-imap/pop3d.pem ]; # file exists
  then
    die "Failed to run mkpop3dcert";
  fi
  logMessage "done\n";

  logMessage "  > Running mkimapdcert... ";
  mkimapdcert;
  if [ $? -ne 0 ] && [ ! -f /etc/courier-imap/imapd.pem ];
  then
    die "Failed to run mkipapcert";
  fi
  logMessage "done\n";

  for FILENM in imapd pop3d;
  do
    logMessage "  > Updating /etc/courier-imap/${FILENM} file... ";
    FILE=/etc/courier-imap/${FILENM}
    META=$(initChangeFile ${FILE});
    setOrUpdateUnquotedVariable PIDFILE /var/run/courier/${FILENM}.pid ${FILE}
    applyMetaOnFile ${FILE} ${META};
    commitChangeFile ${FILE} ${META};
    logMessage "done\n";

    logMessage "  > Updating /etc/courier-imap/${FILENM}-ssl file... ";
    FILE=/etc/courier-imap/${FILENM}-ssl
    META=$(initChangeFile ${FILE});
    setOrUpdateUnquotedVariable SSLPIDFILE /var/run/courier/${FILENM}-ssl.pid ${FILE}
    applyMetaOnFile ${FILE} ${META};
    commitChangeFile ${FILE} ${META};
    logMessage "done\n";
  done

  logMessage "  > Creating /var/run/courier location... ";
  mkdir -p /var/run/courier;
  restorecon -R /var/run/courier;
  logMessage "done\n";
}

startcourier() {
  logMessage "  > Need to start courier!\n";
  logMessage "  > Run /etc/init.d/courier-imapd start\n";
  logMessage "  > Run /etc/init.d/courier-imapd-ssl start\n";
  logMessage "  > Run /etc/init.d/courier-pop3d start\n";
  logMessage "  > Run /etc/init.d/courier-pop3d-ssl start\n";
  die "Please continue with step 'installsasl' when done.";
}

installsasl() {
  logMessage "  > Installing selinux-sasl... ";
  installSoftware -u selinux-sasl || die "Failed to install selinux-sasl"
  logMessage "done\n";

  logMessage "  > Installing cyrus-sasl... "
  installSoftware -u cyrus-sasl || die "Failed to install cyrus-sasl"
  logMessage "done\n";

  logMessage "  > Editing /etc/sasl2/smtpd.conf... ";
  typeset FILE=/etc/sasl2/smtpd.conf;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e '/^mech_list/d' ${FILE};
  sed -i -e '/^pwcheck_method/d' ${FILE};
  echo "mech_list: $(getValue sasl.smtpd.mech_list)" >> ${FILE};
  echo "pwcheck_method: $(getValue sasl.smtpd.pwcheck_method)" >> ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing /etc/conf.d/saslauthd... ";
  FILE=/etc/conf.d/saslauthd
  META=$(initChangeFile ${FILE});
  sed -i -e '/^SASLAUTHD_OPTS=/d' ${FILE};
  echo "SASLAUTHD_OPTS=$(getValue sasl.saslauthd.SASLAUTHD_OPTS)" >> ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";
}

startsasl() {
  logMessage "  > Please run /etc/init.d/saslauthd start\n";
  die "When finished, continue with step certificates.";
}

certificates() {
  logMessage "  > Editing openssl.cnf... ";
  typeset FILE=/etc/ssl/openssl.cnf;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e "s:^countryName_default.*:countryName_default = $(getValue openssl.cnf.countryName_default):g" ${FILE};
  sed -i -e "s:^stateOrProvinceName_default.*:stateOrProvinceName_default = $(getValue openssl.cnf.stateOrProvinceName_default):g" ${FILE};
  sed -i -e "s:^localityName_default.*:localityName_default = $(getValue openssl.cnf.localityName_default):g" ${FILE};
  sed -i -e "s:^0.organizationName_default.*:0.organizationName_default = $(getValue openssl.cnf.0_organizationName_default):g" ${FILE};
  # commonName_default is not given by default
  awk '/^commonName_max/ {print "commonName_default = Foo";} {print}' ${FILE} > ${FILE}.new;
  mv ${FILE}.new ${FILE};
  sed -i -e "s:^commonName_default.*:commonName_default = $(getValue openssl.cnf.commonName_default):g" ${FILE};
  sed -i -e "s:^emailAddress_default.*:emailAddress_default = $(getValue openssl.cnf.emailAddress_default):g" ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  pushd /etc/ssl/misc;

  logMessage "  > Running CA.pl -newreq-nodes... ";
  printf "\n\n\n\n\n\n\n\n\n" | ./CA.pl -newreq-nodes || die "Failed to run CA.pl -newreq-nodes"
  logMessage "done\n";

  logMessage "  > Running CA.pl -newca... ";
  printf "\n$(getValue openssl.CA.privkey_pass)\n$(getValue openssl.CA.privkey_pass)\n\n\n\n\n\n\n\n\n\n$(getValue openssl.CA.privkey_pass)\n" ./CA.pl -newca || die "Failed to run CA.pl -newca"
  logMessage "done\n";

  logMessage "  > Running CA.pl -sign... ";
  printf "$(getValue openssl.CA.privkey_pass)\ny\n" | ./CA.pl -sign || die "Failed to run CA.pl -sign";
  logMessage "done\n";

  logMessage "  > Copying certificates to postfix location... ";
  cp newcert.pem /etc/postfix || die "Failed to copy certificate newcert.pem";
  cp newkey.pem /etc/postfix || die "Failed to copy key newkey.pem";
  cp demoCA/cacert.pem /etc/postfix || die "Failed to copy certificate store cacert.pem";
  logMessage "done\n";

  logMessage "  > Creating certificates for Apache... ";
  printf "$(getValue openssl.httpd.privkey_pass)\n\n\n\n\n\n\n\n\n\n" | openssl req -new > new.cert.csr || die "Failed to create new request certificate";
  printf "$(getValue openssl.httpd.privkey_pass)\n" | openssl rsa -in privkey.pem -out new.cert.key || die "Failed to create new certificate";
  openssl x509 -in new.cert.csr -out new.cert.cert -req -signkey new.cert.key -days 365 || die "Failed to sign certificates";
  logMessage "done\n";

  popd;
}

updatepostfix() {
  logMessage "  > Updating main.cf... ";
  updateEqualNoQuotConfFile postfix.1.main /etc/postfix/main.cf;
  logMessage "done\n";
}

restartpostfix() {
  logMessage "  > Please reload postfix and continue with step 'vmail'\n"
  die "Execute /etc/init.d/postfix reload and continue with step vmail."
}

vmail() {
  logMessage "  > Creating vmail user... ";
  getent passwd vmail;
  if [ $? -ne 0 ];
  then
    useradd -d /home/vmail -s /bin/false -m vmail;
    logMessage "done\n";
  else
    logMessage "skipped\n";
  fi

  logMessage "  > Creating mailbox infrastructure... ";
  mkdir -p /home/vmail/virt-domain.com/foo
  chown -R vmail:vmail /home/vmail/virt-domain.com
  maildirmake /home/vmail/virt-domain.com/foo/.maildir
  logMessage "done\n";
}

installmysql() {
  logMessage "  > Installing MySQL... ";
  installSoftware -u mysql || die "Failed to install MySQL"
  logMessage "done\n";

  logMessage "  > Downloading genericmailsql.sql file... ";
  if [ ! -f genericmailsql.sql ];
  then
    wget $(getValue mysql.genericmailsql.url);
    logMessage "done\n";
  else
    logMessage "skipped\n";
  fi
}

startmysql() {
  logMessage "  > Please run emerge --config mysql (if not already done)\n";
  logMessage "    (Hint: use same password as in mysql.root.password)\n";
  logMessage "  > Next, start mysql (/etc/init.d/mysql start)\n";
  logMessage "  > Finally, run mysql_secure_installation\n";
  die "When finished, continue with loadsql step"
}

loadsql() {
  logMessage "  > Creating mailsql database... ";
  mysqladmin -u root --password=$(getValue mysql.root.password) create mailsql;
  if [ $? -eq 0 ];
  then
    logMessage "done\n";

    logMessage "  > Populating with genericmailsql.sql file... ";
    mysql -u root --password=$(getValue mysql.root.password) mailsql < genericmailsql.sql;
    echo "GRANT SELECT,INSERT,UPDATE,DELETE ON mailsql.* TO mailsql@localhost IDENTIFIED BY \'$(getValye mysql.mailsql.password)\'; FLUSH PRIVILEGES;" | mysql -u root --password=$(getValue mysql.rootpass);
    logMessage "done\n";
  else
    logMessage "skipped\n";
  fi
}

installapache() {
  logMessage "  > Installing apache... ";
  installSoftware -u apache;
  if [ $? -ne 0 ];
  then
    logMessage "failed\n";
    logMessage "    Trying to apply fix (mkdir.sh should be bin_t)... ";
    chcon -t bin_t /usr/share/build-1/mkdir.sh;
    logMessage "done\n";

    logMessage "  > Installing apache (again)... ";
    installSoftware -u apache || die "Failed to install apache";
  fi
  logMessage "done\n";

  logMessage "  > Installing phpmyadmin... ";
  installSoftware -u phpmyadmin || die "Failed to install phpmyadmin... ";
  logMessage "done\n";

  logMessage "  > Setting up SSL keys... ";
  cp /etc/ssl/misc/new.cert.cert /etc/apache2/ssl || die "Copy failed of new.cert.cert";
  cp /etc/ssl/misc/new.cert.key /etc/apache2/ssl || die "Copy failed of new.cert.key";
  logMessage "done\n";
}

setupapache() {
  logMessage "  > Go to /etc/apache2/vhosts.d\n";
  logMessage "  > Create a new conf (copy existing, name it ssl-vhost.conf)\n";
  logMessage "  > Edit ssl-vhost.conf, set NameVirtualHost, ServerName, DocumentRoot, SSL stuff\n";
  logMessage "  > Also, add -D SSL -D PHP5 to the APACHE2_OPTS in /etc/conf.d/apache2\n";
  die "Continue with the phpmyadmin step."
}

phpmyadmin() {
  logMessage "  > Editing config.inc.php... ";
  typeset FILE=/var/www/localhost/htdocs/phpmyadmin;
  cp ${FILE}/config.sample.inc.php ${FILE}/config.inc.php;
  FILE=${FILE}/config.inc.php;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e "s:\(\$cfg\['blowfish_secret'\]\).*:\1 = \'$(getValue phpmyadmin.config.blowfish_secret)\';" ${FILE};
  sed -i -e "s:\(\$cfg\['Servers'\]\[\$i\]\['host'\]\).*:\1 = \'$(getValue phpmyadmin.config.host)\';" ${FILE};
  sed -i -e "s:\(\$cfg\['Servers'\]\[\$i\]\['controluser'\]\).*:\1 = 'mailsql';" ${FILE};
  sed -i -e "s:\(\$cfg\['Servers'\]\[\$i\]\['controlpass'\]\).*:\1 = \'$(getValue mysql.mailsql.password)\';" ${FILE};
  sed -i -e "s:\(\$cfg\['Servers'\]\[\$i\]\['user'\]\).*:\1 = 'mailsql';" ${FILE};
  sed -i -e "s:\(\$cfg\['Servers'\]\[\$i\]\['password'\]\).*:\1 = \'$(getValue mysql.mailsql.password)\';" ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";
}

mysqlauth() {
  logMessage "  > Editing authdaemonrc... ";
  typeset FILE=/etc/courier/authlib/authdaemonrc;
  typeset META=$(initChangeFile ${FILE});
  sed -i -e "s:^\(authmodulelist\).*:\1=\"$(getValue authdaemonrc.authmodulelist)\"" ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing authmysqlrc... ";
  FILE=/etc/courier/authlib/authmysqlrc;
  META=$(initChangeFile ${FILE});
  for VAR in SERVER USERNAME PASSWORD DATABASE USER_TABLE CLEAR_PWFIELD UID_FIELD GID_FIELD LOGIN_FIELD HOME_FIELD NAME_FIELD MAILDIR_FIELD;
  do
    sed -i -e "s:^MYSQL_${VAR}:MYSQL_${VAR}  $(getValue authmysqlrc.MYSQL_${VAR})" ${FILE};
  done
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";
}

restartauth() {
  logMessage "  > Run /etc/init.d/courier-authlib restart\n";
  logMessage "  > Run /etc/init.d/saslauthd restart\n";
  die "Continue with step mysqlpostfix."
}

mysqlpostfix() {
  logMessage "  > Editing mysql-aliases.cf... ";
  typeset FILE=/etc/postfix/mysql-aliases.cf;
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  typeset META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-aliases ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing mysql-relocated.cf... ";
  FILE=/etc/postfix/mysql-relocated.cf;
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-relocated ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing mysql-transport.cf... ";
  FILE=/etc/postfix/mysql-transport.cf;
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-transport ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing mysql-virtual-maps.cf... ";
  FILE=/etc/postfix/mysql-virtual-maps.cf
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-virtual-maps ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing mysql-virtual-maps.cf... ";
  FILE=/etc/postfix/mysql-virtual-maps.cf
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-virtual-uid ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing mysql-virtual-uid.cf... ";
  FILE=/etc/postfix/mysql-virtual-uid.cf
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-virtual-uid ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing mysql-virtual.cf... ";
  FILE=/etc/postfix/mysql-virtual.cf
  if [ ! -f ${FILE} ];
  then
    touch ${FILE};
  fi
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.mysql-virtual ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Editing main.cf... ";
  FILE=/etc/postfix/main.cf;
  META=$(initChangeFile ${FILE});
  updateEqualNoQuotConfFile postfix.3.main ${FILE};
  VMUID=$(id -u vmail);
  VMGID=$(id -g vmail);
  setOrUpdateUnquotedVariable virtual_gid_maps static:${VMGID} ${FILE};
  setOrUpdateUnquotedVariable virtual_minimum_uid ${VMUID} ${FILE};
  setOrUpdateUnquotedVariable virtual_uid_maps static:${VMUID} ${FILE};
  applyMetaOnFile ${FILE} ${META};
  commitChangeFile ${FILE} ${META};
  logMessage "done\n";

  logMessage "  > Setting file permissions... ";
  chmod 640 /etc/postfix/mysql-*.cf;
  chgrp postfix /etc/postfix/mysql-*.cf;
  logMessage "done\n";
}

restartpostfix2() {
  logMessage "  > Please run /etc/init.d/postfix restart";
  die "Continue with squirrelmail";
}

squirrelmail() {
  logMessage "  > Installing squirrelmail... ";
  installSoftware -u squirrelmail || die "Failed to install squirrelmail"
  logMessage "done\n";

  logMessage "  > Configuring squirrelmail... ";
  typeset ATOM=$(qlist -IC squirrelmail);
  typeset SVERS=$(qlist -ICv squirrelmail | sed -e "s:${ATOM}-::g");
  webapp-config -I -h localhost -d /mail squirrelmail ${SVERS} || die "Failed to install squirrelmail";
  logMessage "done\n";
}

stepOK "installpostfix" && (
logMessage ">>> Step \"installpostfix\" starting...\n";
runStep installpostfix;
);
nextStep;

stepOK "startposfix" && (
logMessage ">>> Step \"startpostfix\" starting...\n";
runStep startpostfix;
);
nextStep;

stepOK "installcourier" && (
logMessage ">>> Step \"installcourier\" starting...\n";
runStep installcourier;
);
nextStep;

stepOK "startcourier" && (
logMessage ">>> Step \"startcourier\" starting...\n";
runStep startcourier;
);
nextStep;

stepOK "installsasl" && (
logMessage ">>> Step \"installsasl\" starting...\n";
runStep installsasl;
);
nextStep;

stepOK "startsasl" && (
logMessage ">>> Step \"startsasl\" starting...\n";
runStep startsasl;
);
nextStep;

stepOK "certificates" && (
logMessage ">>> Step \"certificates\" starting...\n";
runStep certificates;
);
nextStep;

stepOK "updatepostfix" && (
logMessage ">>> Step \"updatepostfix\" starting...\n";
runStep updatepostfix;
);
nextStep;

stepOK "restartpostfix" && (
logMessage ">>> Step \"restartpostfix\" starting...\n";
runStep restartpostfix;
);
nextStep;

stepOK "vmail" && (
logMessage ">>> Step \"vmail\" starting...\n";
runStep vmail;
);
nextStep;

stepOK "installmysql" && (
logMessage ">>> Step \"installmysql\" starting...\n";
runStep installmysql;
);
nextStep;

stepOK "startmysql" && (
logMessage ">>> Step \"startmysql\" starting...\n";
runStep startmysql;
);
nextStep;

stepOK "loadsql" && (
logMessage ">>> Step \"loadsql\" starting...\n";
runStep loadsql;
);
nextStep;

stepOK "installapache" && (
logMessage ">>> Step \"installapache\" starting...\n";
runStep installapache;
);
nextStep;

stepOK "setupapache" && (
logMessage ">>> Step \"setupapache\" starting...\n";
runStep installapache;
);
nextStep;

stepOK "phpmyadmin" && (
logMessage ">>> Step \"phpmyadmin\" starting...\n";
runStep phpmyadmin;
);
nextStep;

stepOK "mysqlauth" && (
logMessage ">>> Step \"mysqlauth\" starting...\n";
runStep mysqlauth;
);
nextStep;

stepOK "restartauth" && (
logMessage ">>> Step \"restartauth\" starting...\n";
runStep restartauth;
);
nextStep;

stepOK "mysqlpostfix" && (
logMessage ">>> Step \"mysqlpostfix\" starting...\n";
runStep mysqlpostfix;
);
nextStep;

stepOK "restartpostfix2" && (
logMessage ">>> Step \"restartpostfix2\" starting...\n";
runStep restartpostfix2;
);
nextStep;

stepOK "squirrelmail" && (
logMessage ">>> Step \"squirrelmail\" starting...\n";
runStep squirrelmail;
);
nextStep;

cleanupTools;
rm ${FAILED};
