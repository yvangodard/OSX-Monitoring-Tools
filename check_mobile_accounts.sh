#!/bin/bash

# Check if Mobile Accounts on OS X are synchronized
# by Yvan GODARD
# http://www.yvangodard.me

# v1.0 - 30 November 2015
# Initial release.

## Set up our variables
version="check_mobile_accounts v1.0 - 2015, Yvan Godard [godardyvan@gmail.com] - http://www.yvangodard.me"
currentDate=$(date "+%s")
scriptDir=$(dirname "${0}")
scriptName=$(basename "${0}")
scriptNameWithoutExt=$(echo "${scriptName}" | cut -f1 -d '.')
usersList=$(mktemp /tmp/${scriptNameWithoutExt}_fileUsers.XXXXX)
usersListWithNetworkDirectory=$(mktemp /tmp/${scriptNameWithoutExt}_fileUsers.XXXXX)
messageContent=$(mktemp /tmp/${scriptNameWithoutExt}_messageContent.XXXXX)
filesToTestList=$(mktemp /tmp/${scriptNameWithoutExt}_filesToTestList.XXXXX)
groupsList=$(mktemp /tmp/${scriptNameWithoutExt}_groupsList.XXXXX)
homeDirsPathList=$(mktemp /tmp/${scriptNameWithoutExt}_homeDirsPathList.XXXXX)
ldapGroups=$(mktemp /tmp/${scriptNameWithoutExt}_ldapGroups.XXXXX)
openDirectoryServer="127.0.0.1"
warnDays=""
critDays=""
filterWithGroups=0
personalFilesToTest=0
personalHomeDirsPath=0
numberOfFilesToBeChanged=2
withPercentage=0
filesToTest="com.apple.finder.plist
com.apple.MCX.plist
com.apple.recentitems.plist
.DS_Store
Mail"
homeDirsPath="/users"
help="no"

function help () {
  echo ""
  echo "${version}"
  echo "This script warns or crits if mobile accounts aren't synchronized for a few days."
  echo ""
  echo "Disclamer:"
  echo "This tool is provide without any support and guarantee."
  echo ""
  echo "Synopsis:"
  echo "./${scriptName} [-h] | -w <warn days> -c <crit days>" 
  echo "                           [-g <user groups to process>] [-f <files to test>]"
  echo "                           [-u <opendirectory server>] [-p <homedirs path>]"
  echo "                           [-n <test files to be changed>] [-t <tolerance percentage>]"
  echo ""
  echo "To print this help:"
  echo "   -h:                        prints this help then exit"
  echo ""
  echo "Mandatory options:"
  echo "   -w <warn days>:            Number of days (without full synchronization of all accounts) from which warn."
  echo "   -c <crit days>:            Number of days (without full synchronization of all accounts) from which crit."
  echo ""
  echo "Optional options:"
  echo "   -g <user groups>:          User groups, in OpenDirectory server, the full path of the directory to check."
  echo "                              If you want to check more than one user group, separate groups with '%',"
  echo "                              like 'workgoup%students'."
  echo "                              If not used, all users registered in OpenDirectory server will be tested."
  echo "   -f <files to test>:        Files used to test synchronization in each mobile account,"
  echo "                              separated by '%' character, like 'com.apple.finder.plist%.DS_Store'"
  echo "                              (default: '$(echo ${filesToTest} | perl -p -e 's/ /%/g' | awk '!x[$0]++')')"
  echo "   -u <opendirectory server>: OpenDirectory server address (default: '${openDirectoryServer}')"
  echo "   -p <homedirs path>:        full path of home directories,"
  echo "                              separated by '%' character, like '/users%/PHD'"
  echo "                              (default: '$(echo ${homeDirsPath} | perl -p -e 's/ /%/g' | awk '!x[$0]++')')"
  echo "   -n <files to be changed>:  Number of changed test files necessary to consider that synchronization is OK,"
  echo "                              (default: '${numberOfFilesToBeChanged})."
  echo "   -t <tolerance percentage>: Percentage of non-synchronized accounts over which to warn or crit."
  echo "                              If not used, warns or crits from the first unsynchronized account."
  echo "                              You can use the same value for warn and crit (eg.: '-t 15'),"
  echo "                              or two values for warn and crit, separated by %, as '-t warn%crit'."
}

function alldone () {
  # Prints message
  [[ ! -z ${2} ]] && echo ${2}
  [[ ! -z $(cat ${messageContent}) ]] && echo "" && cat ${messageContent}
  # Remove temp files
  ls /tmp/${scriptNameWithoutExt}* > /dev/null 2>&1
  [[ $? -eq 0 ]] && rm -R /tmp/${scriptNameWithoutExt}*
  exit ${1}
}

function testInteger () {
  test ${1} -eq 0 2>/dev/null
  if [[ $? -eq 2 ]]; then
    echo 0
  else
    echo 1
  fi
}

function testMemberOfGroup () {
  [[ $# -ne 2 ]] && alldone 3 "FATAL ERROR - Function 'testMemberOfGroup' used without mandatory parameters!"
  dsmemberutil checkmembership -U "$1" -G "$2" | grep "is a member" > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo 1
  else
    echo 0
  fi 
}

# Parameters tests
optsCount=0
while getopts "hw:c:g:f:u:p:n:t:" option
do
    case "$option" in
      h)  help="yes"
          ;;
      w)  warnDays=${OPTARG}
          let optsCount=${optsCount}+1
          ;;
      c)  critDays=${OPTARG}
          let optsCount=${optsCount}+1
          ;;
      g)  if [[ ! -z ${OPTARG} ]]; then
            filterWithGroups=1
            echo ${OPTARG} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${groupsList}
          else
            echo "> You tried to use '-g' option without any groupname in argument." >> ${messageContent}
            echo "  So, we continue the process for all users registered in OpenDirectory server." >> ${messageContent}
            echo "" >> ${messageContent}
          fi
          ;;
      f)  if [[ ! -z ${OPTARG} ]]; then
            personalFilesToTest=1
            echo ${OPTARG} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${filesToTestList}
          else
            echo "> You tried to use '-f' option without any file in argument." >> ${messageContent}
            echo "  So, we continue the process without default files:" >> ${messageContent}
            for file in ${filesToTest}; do
              echo "  - ${file}" >> ${messageContent}
            done
            echo "" >> ${messageContent}

          fi
          ;;
      u)  openDirectoryServer=${OPTARG}
          ;;
      p)  if [[ ! -z ${OPTARG} ]]; then
            personalHomeDirsPath=1
            echo ${OPTARG} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${homeDirsPathList}
          else
            echo "> You tried to use '-p' option without any directory in argument." >> ${messageContent}
            echo "  So, we continue the process with the default path '${homeDirsPath}'." >> ${messageContent}
            echo "" >> ${messageContent}
          fi
          ;;
      n)  if [[ $(testInteger ${OPTARG}) -ne 1 ]]; then
            echo "> You tried to use '-n ${OPTARG}' option without an integer in argument." >> ${messageContent}
            echo "  So, we continue the process with the default value '${numberOfFilesToBeChanged}'." >> ${messageContent}
            echo "" >> ${messageContent}
          else
            numberOfFilesToBeChanged=${OPTARG}
          fi
          ;;
      t)  echo ${OPTARG} | grep % > /dev/null 2>&1
          if [[ $? -ne 0 ]]; then
            if [[ $(testInteger ${OPTARG}) -ne 1 ]]; then
              echo "> You tried to use '-t ${OPTARG}' option without an integer in argument." >> ${messageContent}
              echo "  So, we continue the process without option '-t'." >> ${messageContent}
              echo "" >> ${messageContent}
            else
              critPercentage=${OPTARG}
              warnPercentage=${OPTARG}
              withPercentage=1
            fi
          else
            warnPercentage=$(echo ${OPTARG} | cut -d ""%"" -f 1)
            critPercentage=$(echo ${OPTARG} | cut -d ""%"" -f 2)
            if [[ $(testInteger ${warnPercentage}) -ne 1 ]]; then
              echo "> You tried to use '-t ${OPTARG}' but ${warnPercentage} (warn value) is not an integer." >> ${messageContent}
              echo "  So, we continue the process without option '-t'." >> ${messageContent}
              echo "" >> ${messageContent}
            elif [[ $(testInteger ${critPercentage}) -ne 1 ]]; then
              echo "> You tried to use '-t ${OPTARG}' but ${critPercentage} (crit value) is not an integer." >> ${messageContent}
              echo "  So, we continue the process without option '-t'." >> ${messageContent}
              echo "" >> ${messageContent}
            else
              withPercentage=1
              if [[ ${critPercentage} -lt ${warnPercentage} ]]; then
                echo "> You tried to use '-t ${OPTARG}' but ${critPercentage} (crit %) is not greater (or equal) than ${warnPercentage} (warn %)." >> ${messageContent}
                echo "  So, we continue the process with option '-t ${critPercentage}%${critPercentage}'." >> ${messageContent}
                echo "" >> ${messageContent}
                warnPercentage=${critPercentage}
              fi
            fi
          fi
          ;;
    esac
done

# Prints help
[[ ${help} = "yes" ]] && help && alldone 0

# Test mandatory options
[[ "${warnDays}" == "" ]] && echo "> You must provide a delay (in days) with -w!" >> ${messageContent}
[[ "${critDays}" == "" ]] && echo "> You must provide a delay (in days) with -c!" >> ${messageContent}
[[ ${optsCount} != "2" ]] && alldone 3 "FATAL ERROR - All mandatory options are not filled."

#  Test root access
[[ `whoami` != 'root' ]] && alldone 3 "FATAL ERROR - This tool needs a root access. Use 'sudo'."

# Test if -w and -c are integers
[[ $(testInteger ${warnDays}) -ne 1 ]] && alldone 3 "ERROR - Option -w have to be an integer."
[[ $(testInteger ${critDays}) -ne 1 ]] && alldone 3 "ERROR - Option -c have to be an integer."

# Coherence tests
[[ ${critDays} -lt ${warnDays} ]] && alldone 2 "ERROR - Option -c have to be greater than (or equal) -w."

# Test groups
if [[ ${filterWithGroups} == "1" ]]; then
  for group in $(cat ${groupsList}); do
    dscl /LDAPv3/${openDirectoryServer} -list /Groups | grep ^${group}$ >> ${ldapGroups}
  done
  if [[ -z $(cat ${ldapGroups}) ]]; then
    echo "> You tried to use '-g' option without any groupname registered in OpenDirectory in argument." >> ${messageContent}
    echo "  So, we continue the process for all users registered in OpenDirectory server." >> ${messageContent}
    echo "" >> ${messageContent}
    filterWithGroups=0
  fi
fi

# Creating user list
if [[ ${filterWithGroups} == "0" ]]; then
  dscl /LDAPv3/${openDirectoryServer} -list /Users >> ${usersList}
elif [[ ${filterWithGroups} == "1" ]]; then
  for user in $(dscl /LDAPv3/${openDirectoryServer} -list /Users); do
    userIsMemberOfOneOrMoreGroups=0
    for group in $(cat ${ldapGroups}); do
      [[ $(testMemberOfGroup ${user} ${group}) -eq 1 ]] && userIsMemberOfOneOrMoreGroups=1
    done
    [[ ${userIsMemberOfOneOrMoreGroups} -eq 1 ]] && echo "${user}" >> ${usersList}
  done
fi

# Test if list of users is not empty
[[ -z $(cat ${usersList}) ]] && alldone 3 "FATAL ERROR - No user to process. Please verify your configuration."

# Test if user has a network home directory
for user in $(cat ${usersList} | sort -u); do
  dscl /LDAPv3/${openDirectoryServer} -read /Users/${user} HomeDirectory 2> /dev/null | grep -v "No such key" > /dev/null 2>&1
  [[ $? -eq 0 ]] && echo ${user} >> ${usersListWithNetworkDirectory}
done

# Test if list of users is not empty
[[ -z $(cat ${usersListWithNetworkDirectory}) ]] && alldone 3 "FATAL ERROR - No user with Network Home Directory. Please verify your configuration."

# List of files to test
if [[ ${personalFilesToTest} -eq 0 ]]; then
  for file in ${filesToTest}; do
    echo "${file}" >> ${filesToTestList}
  done
fi

# Directories
[[ ${personalHomeDirsPath} -eq 0 ]] && echo ${homeDirsPath} > ${homeDirsPathList}

## Processing each user
echo "************************************************************************************" >> ${messageContent}
echo "********************************* PROCESSING USERS *********************************" >> ${messageContent}
echo "************************************************************************************" >> ${messageContent}
echo "" >> ${messageContent}

numberOfUsers=0
numberOfUsersWithoutSyncCrit=0
numberOfUsersWithoutSyncWarn=0
for user in $(cat ${usersListWithNetworkDirectory}); do
  thisUserIsWarn=0
  thisUserIsCrit=0
  echo "> Processing user ${user}" >> ${messageContent}
  for actualHomeDir in $(cat ${homeDirsPathList}); do
    if [ -d ${actualHomeDir%/}/${user} ]; then
      echo "  Test in '${actualHomeDir%/}/${user}'" >> ${messageContent}
      warnFilesChanged=0
      critFilesChanged=0
      for fileToTest in $(cat ${filesToTestList}); do
        [[ ! -z $(find ${actualHomeDir%/}/${user} -maxdepth 3 -a -mtime -${critDays} -a -name ${fileToTest}) ]] && let critFilesChanged=${critFilesChanged}+1
        [[ ! -z $(find ${actualHomeDir%/}/${user} -maxdepth 3 -a -mtime -${warnDays} -a -name ${fileToTest}) ]] && let warnFilesChanged=${warnFilesChanged}+1
      done
      if [[ ${critFilesChanged} -lt ${numberOfFilesToBeChanged} ]]; then
        if [[ ${critFilesChanged} -le 1 ]]; then
          echo "  CRIT: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -le 1 ]] && echo "  WARN: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -ge 2 ]] && echo "  WARN: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
        elif [[ ${critFilesChanged} -ge 2 ]]; then
          echo "  CRIT: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -le 1 ]] && echo "  WARN: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -ge 2 ]] && echo "  WARN: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
        fi
        echo "  **** CRIT ****" >> ${messageContent}
        thisUserIsCrit=1
        thisUserIsWarn=1
      elif [[ ${warnFilesChanged} -lt ${numberOfFilesToBeChanged} ]]; then
        if [[ ${warnFilesChanged} -le 1 ]]; then
          echo "  WARN: ${warnFilesChanged} file changed since ${warnDays} days, but not CRIT, because:" >> ${messageContent}
          [[ ${critFilesChanged} -le 1 ]] && echo "  CRIT: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -ge 2 ]] && echo "  CRIT: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
        elif [[ ${warnFilesChanged} -ge 2 ]]; then
          echo "  WARN: ${warnFilesChanged} files changed since ${warnDays} days, but not CRIT, because:" >> ${messageContent}
          [[ ${critFilesChanged} -le 1 ]] && echo "  CRIT: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -ge 2 ]] && echo "  CRIT: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
        fi
        echo "  **** WARN ****" >> ${messageContent}
        thisUserIsWarn=1
      else
        if [[ ${critFilesChanged} -le 1 ]]; then
          echo "  CRIT: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -le 1 ]] && echo "  WARN: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -ge 2 ]] && echo "  WARN: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
        elif [[ ${critFilesChanged} -ge 2 ]]; then
          echo "  CRIT: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -le 1 ]] && echo "  WARN: ${critFilesChanged} file changed since ${critDays} days." >> ${messageContent}
          [[ ${critFilesChanged} -ge 2 ]] && echo "  WARN: ${critFilesChanged} files changed since ${critDays} days." >> ${messageContent}
        fi
        echo "  ***** OK *****" >> ${messageContent}
      fi
    fi
  done
  echo "" >> ${messageContent}
  let numberOfUsers=${numberOfUsers}+1
  [[ ${thisUserIsCrit} -eq 1 ]] && let numberOfUsersWithoutSyncCrit=${numberOfUsersWithoutSyncCrit}+1
  [[ ${thisUserIsWarn} -eq 1 ]] && let numberOfUsersWithoutSyncWarn=${numberOfUsersWithoutSyncWarn}+1
done

## Overviews
echo "************************************************************************************" >> ${messageContent}
echo "************************************* OVERVIEW *************************************" >> ${messageContent}
echo "************************************************************************************" >> ${messageContent}
echo "" >> ${messageContent}

pctCrit=$((${numberOfUsersWithoutSyncCrit}*100/${numberOfUsers}))
pctWarn=$((${numberOfUsersWithoutSyncWarn}*100/${numberOfUsers}))
pctCritRd=$(printf "%.0f" $(echo "scale=2;$pctCrit" | bc))
pctWarnRd=$(printf "%.0f" $(echo "scale=2;$pctWarn" | bc))

echo "Number of accounts: ${numberOfUsers}" >> ${messageContent}
echo "Number of accounts without sync crit: ${numberOfUsersWithoutSyncCrit} - ${pctCritRd}%" >> ${messageContent}
echo "Number of accounts without sync warn: ${numberOfUsersWithoutSyncWarn} - ${pctWarnRd}%" >> ${messageContent}

if [[ ${withPercentage} -eq 0 ]]; then
  outputValues="CriticalPHD=${numberOfUsersWithoutSyncCrit} WarningPHD=${numberOfUsersWithoutSyncWarn}"
  if [[ ${numberOfUsersWithoutSyncCrit} -ge 1 ]]; then
    [[ ${numberOfUsersWithoutSyncCrit} -le 1 ]] && alldone 2 "CRITICAL - ${numberOfUsersWithoutSyncCrit}/${numberOfUsers} mobile accounts is not synced|${outputValues}"
    [[ ${numberOfUsersWithoutSyncCrit} -gt 1 ]] && alldone 2 "CRITICAL - ${numberOfUsersWithoutSyncCrit}/${numberOfUsers} mobile accounts aren't synced|${outputValues}"
  elif [[ ${numberOfUsersWithoutSyncWarn} -ge 1 ]]; then
    [[ ${numberOfUsersWithoutSyncWarn} -le 1 ]] && alldone 1 "WARNING - ${numberOfUsersWithoutSyncWarn}/${numberOfUsers} mobile accounts is not synced|${outputValues}"
    [[ ${numberOfUsersWithoutSyncWarn} -gt 1 ]] && alldone 1 "WARNING - ${numberOfUsersWithoutSyncWarn}/${numberOfUsers} mobile accounts aren't synced|${outputValues}"
  else
    alldone 0 "OK|${outputValues}"
  fi 
elif [[ ${withPercentage} -eq 1 ]]; then
  outputValues="CriticalPHD=${pctCritRd}%;${critPercentage};;0;100 WarningPHD=${pctWarnRd}%;${warnPercentage};;0;100"
  if [[ ${pctCritRd} -ge ${critPercentage} ]]; then
    alldone 2 "CRITICAL - ${numberOfUsersWithoutSyncCrit}/${numberOfUsers} mobile accounts aren't synced|${outputValues}"
  elif [[ ${pctWarnRd} -ge ${warnPercentage} ]]; then
    alldone 1 "WARNING - ${numberOfUsersWithoutSyncWarn}/${numberOfUsers} mobile accounts aren't synced|${outputValues}"
  else
    alldone 0 "OK|${outputValues}"
  fi
fi
alldone 0