#!/bin/sh

#set -x;

if [ $# -ne 3 ];
then
  echo "Usage: $0 <xccdf-template> <oval-namespace> <save-dir>";
  echo "";
  echo " xccdf-template: Filename of the XCCDF template (must end in .template)";
  echo " oval-namespace: Namespace for the OVAL objects, like \"org.gentoo.dev.swift\"";
  echo " save-dir:       Directory in which to save the results (can be \".\")";
  exit 1;
fi

typeset XCCDF=$1;
typeset OVALNS=$2;
typeset OVAL=$(echo ${XCCDF} | sed -e 's:.template::g' | sed -e 's:[Xx][Cc][Cc][Dd][Ff]:oval:g');
typeset WORKDIR=$3;

# Error checking
if [ ! -f ${XCCDF} ];
then
  echo "File ${XCCDF} must exist!";
  exit 2;
fi

if [ ! -d ${WORKDIR} ];
then
  echo "Directory ${WORKDIR} must exist!";
  exit 3;
fi

if [ -f ${WORKDIR}/${OVAL} ];
then
  TIMESTAMP=$(date +%Y%m%d%H%M%S.%N);
  echo "File ${OVAL} already exists. Renaming to ${OVAL}.${TIMESTAMP}";
  mv ${WORKDIR}/${OVAL} ${WORKDIR}/${OVAL}.${TIMESTAMP};
fi

# Loading in libraries
for LIB in ./lib/*.sh;
do
  echo "Loading in ${LIB}...";
  source ${LIB};
done

# Preparing the work directory
cp ${XCCDF} ${WORKDIR}/${XCCDF%%.template};
XCCDF=${XCCDF%%.template};
cp definitions.conf ${WORKDIR} > /dev/null 2>&1;

pushd ${WORKDIR} > /dev/null 2>&1;
touch objects.conf;
touch states.conf;

###
### HERE STARTS THE REAL WORK
###
cat > ${OVAL} << EOF
<?xml version="1.0"?>
<oval_definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
 xmlns="http://oval.mitre.org/XMLSchema/oval-definitions-5"
 xmlns:oval="http://oval.mitre.org/XMLSchema/oval-common-5"
 xmlns:oval-def="http://oval.mitre.org/XMLSchema/oval-definitions-5"
 xmlns:ind-def="http://oval.mitre.org/XMLSchema/oval-definitions-5#independent"
 xmlns:lin-def="http://oval.mitre.org/XMLSchema/oval-definitions-5#linux"
 xmlns:unix-def="http://oval.mitre.org/XMLSchema/oval-definitions-5#unix">
  <generator>
    <oval:product_name>vim</oval:product_name>
    <oval:schema_version>5.9</oval:schema_version>
    <oval:timestamp>2011-10-31T12:00:00-04:00</oval:timestamp>
  </generator>

<definitions>
EOF

##
## Regenerate XCCDF file and OVAL definitions based on definitions.conf.
##
for RULE in $(sed -e 's:.*\[\([^[]*\)\]$:\1:g' definitions.conf);
do
  LINE=$(grep ${RULE} definitions.conf | sed -e 's: \[[^[]*\]$::g');
  LINENUM=$(grep -n "\[${RULE}\]" definitions.conf | sed -e 's|:.*||g');
  grep -q "@@GEN START ${RULE} " ${XCCDF} || continue;

  # XCCDF
  grep -B 99999 "@@GEN START ${RULE} " ${XCCDF} > ${XCCDF}.work;
  echo "<Rule id=\"${RULE}\">" >> ${XCCDF}.work;
  echo "  <title>${LINE}</title>" >> ${XCCDF}.work;
  echo "  <description>${LINE}</description>" >> ${XCCDF}.work;
  if `hasFix`;
  then
    genFix >> ${XCCDF}.work;
  fi
  echo "  <check system=\"http://oval.mitre.org/XMLSchema/oval-definitions-5\">" >> ${XCCDF}.work;
  echo "    <check-content-ref name=\"oval:${OVALNS}:def:${LINENUM}\" href=\"${OVAL}\" />" >> ${XCCDF}.work;
  echo "  </check>" >> ${XCCDF}.work;
  echo "</Rule>" >> ${XCCDF}.work;
  grep -A 99999 "@@GEN END ${RULE} " ${XCCDF} >> ${XCCDF}.work;
  mv ${XCCDF}.work ${XCCDF};

  # OVAL
  echo "<definition class=\"compliance\" id=\"oval:${OVALNS}:def:${LINENUM}\" version=\"1\">" >> ${OVAL};
  echo "  <metadata>" >> ${OVAL};
  echo "    <title>${LINE}</title>" >> ${OVAL};
  echo "    <description>${LINE}</description>" >> ${OVAL};
  echo "  </metadata>" >> ${OVAL};
  echo "  <criteria>" >> ${OVAL};
  echo "    <criterion test_ref=\"oval:${OVALNS}:tst:${LINENUM}\" comment=\"${LINE}\" />" >> ${OVAL};
  echo "  </criteria>" >> ${OVAL};
  echo "</definition>" >> ${OVAL};
done

echo "</definitions>" >> ${OVAL};
echo "" >> ${OVAL};
echo "<tests>" >> ${OVAL};

##
## Loop over definitions to generate tests
##
for RULE in $(sed -e 's:.*\[\([^[]*\)\]$:\1:g' definitions.conf);
do
  LINE=$(grep ${RULE} definitions.conf | sed -e "s: \[${RULE}\]$::g");
  LINENUM=$(grep -n "\[${RULE}\]" definitions.conf | sed -e 's|:.*||g');

  ## Test for separate file system
  echo ${LINE} | egrep -q '^/[^ ]* is (a )?(separate )?file[ ]?system( of type [^ ]+)?$';
  if [ $? -eq 0 ];
  then
    PARTITION=$(echo ${LINE} | sed -e 's:^/\([^ ]*\).*:\1:g');
    TYPE=$(echo ${LINE} | sed -e 's:.*type \([^ ]*\).*:\1:g' -e 's:.* .*::g');
    OBJNUM=$(grep ":partition=${PARTITION}:" objects.conf | awk -F':' '{print $1}');
    STENUM=$(grep ":filesystemtype=${TYPE}:" states.conf | awk -F':' '{print $1}');
    if [ "${OBJNUM}" == "" ];
    then
      # Definition doesn't exist yet
      NEWOBJNUM=$(wc -l objects.conf | awk '{print $1+1}');
      echo "${NEWOBJNUM}:partition=${PARTITION}:" >> objects.conf;
      OBJNUM=${NEWOBJNUM};
    fi
    if [ "${STENUM}" == "" ] && [ "${TYPE}" != "" ];
    then
      # State doesn't exist yet
      NEWSTENUM=$(wc -l states.conf | awk '{print $1+1}');
      echo "${NEWSTENUM}:filesystemtype=${TYPE}:" >> states.conf;
      STENUM=${NEWSTENUM};
    fi
    echo "<lin-def:partition_test id=\"oval:${OVALNS}:tst:${LINENUM}\" version=\"1\" check=\"all\" comment=\"${LINE}\" check_existence=\"at_least_one_exists\">" >> ${OVAL};
    echo "  <lin-def:object object_ref=\"oval:${OVALNS}:obj:${OBJNUM}\" />" >> ${OVAL};
    if [ "${TYPE}" != "" ];
    then
      echo "  <lin-def:state state_ref=\"oval:${OVALNS}:ste:${STENUM}\" />" >> ${OVAL};
    fi
    echo "</lin-def:partition_test>" >> ${OVAL};
    continue;
  fi

  ## Test for mount option
  echo ${LINE} | egrep -q 'mount[ ]?point /[^ ]* is mounted with .*option.*';
  if [ $? -eq 0 ];
  then
    PARTITION=$(echo ${LINE} | sed -e 's:^mount point /::g' -e 's: .*::g');
    OPTION=$(echo ${LINE} | sed -e 's:.*option \([a-zA-Z0-9]*\):\1:g' -e 's:.* \([a-zA-Z0-9]*\) option:\1:g');
    OBJNUM=$(grep ":partition=${PARTITION}:" objects.conf | awk -F':' '{print $1}');
    STENUM=$(grep ":mountoption=${OPTION}:" states.conf | awk -F':' '{print $1}');
    if [ "${OBJNUM}" == "" ];
    then
      # Definition doesn't exist yet
      NEWOBJNUM=$(wc -l objects.conf | awk '{print $1+1}');
      echo "${NEWOBJNUM}:partition=${PARTITION}:" >> objects.conf;
      OBJNUM=${NEWOBJNUM};
    fi
    if [ "${STENUM}" == "" ];
    then
      # State doesn't exist yet
      NEWSTENUM=$(wc -l states.conf | awk '{print $1+1}');
      echo "${NEWSTENUM}:mountoption=${OPTION}:" >> states.conf;
      STENUM=${NEWSTENUM};
    fi
    echo "<lin-def:partition_test id=\"oval:${OVALNS}:tst:${LINENUM}\" version=\"1\" check=\"all\" comment=\"${LINE}\" check_existence=\"at_least_one_exists\">" >> ${OVAL};
    echo "  <lin-def:object object_ref=\"oval:${OVALNS}:obj:${OBJNUM}\" />" >> ${OVAL};
    echo "  <lin-def:state state_ref=\"oval:${OVALNS}:ste:${STENUM}\" />" >> ${OVAL};
    echo "</lin-def:partition_test>" >> ${OVAL};
  fi

  ## Test for file regular expression
  echo ${LINE} | egrep -q '^file .* must have a line that matches.*';
  if [ $? -eq 0 ];
  then
    FILE=$(echo ${LINE} | sed -e 's:file \(.*\) must have a line.*:\1:g');
    REGEXP=$(echo "${LINE}" | sed -e 's:.*must have a line that matches ::g');
    OBJNUM=$(grep ":file=${FILE}:" objects.conf | awk -F':' '{print $1}');
    STENUM=$(grep -F ":regexp=${REGEXP}:" states.conf | awk -F':' '{print $1}');
    if [ "${OBJNUM}" == "" ];
    then
      # Definition doesn't exist yet
      NEWOBJNUM=$(wc -l objects.conf | awk '{print $1+1}');
      echo "${NEWOBJNUM}:file=${FILE}:" >> objects.conf;
      OBJNUM=${NEWOBJNUM};
    fi
    if [ "${STENUM}" == "" ];
    then
      # State doesn't exist yet
      NEWSTENUM=$(wc -l states.conf | awk '{print $1+1}');
      echo "${NEWSTENUM}:regexp=${REGEXP}:" >> states.conf;
      STENUM=${NEWSTENUM};
    fi
    echo "<ind-def:textfilecontent54_test id=\"oval:${OVALNS}:tst:${LINENUM}\" version=\"1\" check=\"at least one\" comment=\"${LINE}\" check_existence=\"at_least_one_exists\">" >> ${OVAL};
    echo "  <ind-def:object object_ref=\"oval:${OVALNS}:obj:${OBJNUM}\" />" >> ${OVAL};
    echo "  <ind-def:state state_ref=\"oval:${OVALNS}:ste:${STENUM}\" />" >> ${OVAL};
    echo "</ind-def:textfilecontent54_test>" >> ${OVAL};
  fi

  ## Test for NO file regular expression
  echo ${LINE} | egrep -q 'file .* may not have a line that matches.*';
  if [ $? -eq 0 ];
  then
    FILE=$(echo ${LINE} | sed -e 's:file \(.*\) may not have a line.*:\1:g');
    REGEXP=$(echo ${LINE} | sed -e 's:.*may not have a line that matches ::g' -e 's: \[[^[]*\]$::g');
    OBJNUM=$(grep ":file=${FILE}:" objects.conf | awk -F':' '{print $1}');
    STENUM=$(grep ":regexp=${REGEXP}:" states.conf | awk -F':' '{print $1}');
    if [ "${OBJNUM}" == "" ];
    then
      # Definition doesn't exist yet
      NEWOBJNUM=$(wc -l objects.conf | awk '{print $1+1}');
      echo "${NEWOBJNUM}:file=${FILE}:" >> objects.conf;
      OBJNUM=${NEWOBJNUM};
    fi
    if [ "${STENUM}" == "" ];
    then
      # State doesn't exist yet
      NEWSTENUM=$(wc -l states.conf | awk '{print $1+1}');
      echo "${NEWSTENUM}:regexp=${REGEXP}:" >> states.conf;
      STENUM=${NEWSTENUM};
    fi
    echo "<ind-def:textfilecontent54_test id=\"oval:${OVALNS}:tst:${LINENUM}\" version=\"1\" check=\"none satisfy\" comment=\"${LINE}\" check_existence=\"at_least_one_exists\">" >> ${OVAL};
    echo "  <ind-def:object object_ref=\"oval:${OVALNS}:obj:${OBJNUM}\" />" >> ${OVAL};
    echo "  <ind-def:state state_ref=\"oval:${OVALNS}:ste:${STENUM}\" />" >> ${OVAL};
    echo "</ind-def:textfilecontent54_test>" >> ${OVAL};
  fi

  ## Test for sysctl
  if `sysctlMatches`;
  then
    FILE=$(sysctlFile);
    REGEXP=$(sysctlRegexp);
    OBJNUM=$(getObjnum "file" "${FILE}");
    STENUM=$(getStenum "regexp" "${REGEXP}");

    genTextfileMatch "at least one" >> ${OVAL};
  fi

done

echo "</tests>" >> ${OVAL};
echo "" >> ${OVAL};
echo "<objects>" >> ${OVAL};

##
## Loop over objects.conf to generate objects
##
for OBJECT in $(cat objects.conf);
do
  OBJNUM=$(echo ${OBJECT} | awk -F':' '{print $1}');
  OBJTYPE=$(echo ${OBJECT} | awk -F':' '{print $2}' | awk -F'=' '{print $1}');
  OBJVALUE=$(echo ${OBJECT} | awk -F':' '{print $2}' | awk -F'=' '{print $2}');

  ## Partition objects
  if [ "${OBJTYPE}" == "partition" ];
  then
    echo "<lin-def:partition_object id=\"oval:${OVALNS}:obj:${OBJNUM}\" version=\"1\" comment=\"The /${OBJVALUE} partition\">" >> ${OVAL};
    echo "  <lin-def:mount_point>/${OBJVALUE}</lin-def:mount_point>" >> ${OVAL};
    echo "</lin-def:partition_object>" >> ${OVAL};
    continue;
  fi

  ## File content lines (non-commented)
  if [ "${OBJTYPE}" == "file" ];
  then
    echo "<ind-def:textfilecontent54_object id=\"oval:${OVALNS}:obj:${OBJNUM}\" version=\"1\" comment=\"Non-comment lines in ${OBJVALUE}\">" >> ${OVAL};
    echo "  <ind-def:filepath>${OBJVALUE}</ind-def:filepath>" >> ${OVAL};
    echo "  <ind-def:pattern operation=\"pattern match\">^[[:space:]]*([^#[:space:]].*[^[:space:]]?)[[:space:]]*$</ind-def:pattern>" >> ${OVAL};
    echo "  <ind-def:instance datatype=\"int\" operation=\"greater than or equal\">1</ind-def:instance>" >> ${OVAL};
    echo "</ind-def:textfilecontent54_object>" >> ${OVAL};
  fi
done

echo "</objects>" >> ${OVAL};
echo "" >> ${OVAL};
echo "<states>" >> ${OVAL};

##
## Loop over states.conf to generate states
##
while read STATE;
do
  STENUM=$(echo ${STATE} | awk -F':' '{print $1}');
  STETYPE=$(echo ${STATE} | awk -F':' '{print $2}' | awk -F'=' '{print $1}');
  STEVALUE=$(echo "${STATE}" | awk -F':' '{print $2}' | awk -F'=' '{print $2}');

  # filesystemtype
  if [ "${STETYPE}" == "filesystemtype" ];
  then
    echo "<lin-def:partition_state id=\"oval:${OVALNS}:ste:${STENUM}\" version=\"1\" comment=\"The file system is ${STEVALUE}\">" >> ${OVAL};
    case ${STEVALUE} in
	"tmpfs")
		echo "    <lin-def:fs_type>TMPFS_MAGIC</lin-def:fs_type>" >> ${OVAL};
		;;
	*)
		echo "    <lin-def:fs_type>${STEVAL}</lin-def:fs_type>" >> ${OVAL};
		echo "WARNING - File system type ${STEVAL} does not have a known MAGIC!";
		;;
    esac
    echo "</lin-def:partition_state>" >> ${OVAL};
    continue;
  fi

  # mountoption
  if [ "${STETYPE}" == "mountoption" ];
  then
    echo "<lin-def:partition_state id=\"oval:${OVALNS}:ste:${STENUM}\" version=\"1\" comment=\"The mount option ${STEVALUE} is set\">" >> ${OVAL};
    echo "  <lin-def:mount_options entity_check=\"at least one\">${STEVALUE}</lin-def:mount_options>" >> ${OVAL};
    echo "</lin-def:partition_state>" >> ${OVAL};
    continue;
  fi;

  # regular expressions
  if [ "${STETYPE}" == "regexp" ];
  then
    echo "<ind-def:textfilecontent54_state id=\"oval:${OVALNS}:ste:${STENUM}\" version=\"1\" comment=\"The match of ${STEVALUE}\">" >> ${OVAL};
    echo "  <ind-def:subexpression operation=\"pattern match\">${STEVALUE}</ind-def:subexpression>" >> ${OVAL};
    echo "</ind-def:textfilecontent54_state>" >> ${OVAL};
  fi
done < states.conf;

echo "</states>" >> ${OVAL};
echo "</oval_definitions>" >> ${OVAL};

popd > /dev/null 2>&1;
