#!/bin/bash
#
#  AUTHOR: michael mcdonald
# CONTACT: michael@liquidweb.com
# VERSION: 2.0
# PURPOSE: this will make some recommendations on tuning your MySQL
#          configuration based on your current database and memory usage


VERSION="2.0.2"


################################################################################################
#                                     BEGIN SCRIPT VARIABLES                                   #
#----------------------------------------------------------------------------------------------#

# Color variables for use throughout the script
MEMORYINFO=$(tput setaf 180)
MYSQLINFO=$(tput setaf 74)
RECOMMENDATIONS=$(tput setaf 42)
LIGHT=$(tput setaf 24)
DARK=$(tput setaf 202)
UNDERLINE=$(tput smul)
RESET=$(tput sgr0)


#----------------------------------MYSQL VERSION VARIABLES-------------------------------------#

CURRENT=$(curl -Lks version.report/mysql)

# Acquire the MySQL related information that we'll be working with (specifically the version stuff)
MYSQLOUTPUT=$(mysql -V 2>/dev/null)

# Parse the output of $MYSQLOUTPUT and acquire just the version information
MYSQLVERSION=$(awk '{gsub(/,/,""); print $5}'i <<< "$MYSQLOUTPUT")

# Examines the version of MySQL as gathered from the $MYSQLVERSION variable, then captures into individual groups the
# major, minor, and build values. The individual breakdown of the version number is there in case any type of logic
# needs to be used to examine version numbers against one another. More for historical / future uses than anything.

MYSQLREGEX="(([0-9])\.([0-9]+)\.([0-9]+)).*$"
[[ $MYSQLVERSION =~ $MYSQLREGEX ]] &&
MYSQLENTIREVERSION=${BASH_REMATCH[1]} && # The whole version #: x.x.xx
MYSQLMAJORVERSION=${BASH_REMATCH[2]} &&  # The major version #: x
MYSQLMINORVERSION=${BASH_REMATCH[3]} &&  # The minor version #: x
MYSQLBUILDVERSION=${BASH_REMATCH[4]}     # The build version #: xx

#----------------------------------MYSQL CONF FILE VARIABLE------------------------------------#

# Acquire the contents of the my.cnf file for parsing
MYSQLCONF=$(cat /etc/my.cnf 2>/dev/null)

#-------------------------------INNODB BUFFER POOL SIZE VARIABLES------------------------------#


# Search the $MYSQLCONF variable for the InnoDB Buufer Pool variable. This is just goign to identify if it's there or not
INNODBPRESENT=$(awk '/innodb_buffer_pool_size/' <<< "$MYSQLCONF")

# This will take the value that's assigned to the InnoDB Buffer Pool (should it exist) and store the value
INNODBVALUE=$(awk -F"=" '/innodb_buffer_pool_size/ {print $2}'i <<< "$MYSQLCONF")

# Grabs just the value for the buffer pool
INNODBVALNUMREGEX="(([0-9]+)).*$"
[[ $INNODBVALUE =~ $INNODBVALNUMREGEX ]] &&
INNODBNUMVALUE=${BASH_REMATCH[1]} # Only the value

#Grabs just the alpha character denoting the memory denomination
INNODBVALALPHREGEX="([A-Za-z]).*$"
[[ $INNODBVALUE =~ $INNODBVALALPHREGEX ]] &&
INNODBDENOM=${BASH_REMATCH[1]} # The memory denomination being used

# This calculates what the value would be in MiB since it may be written out in bytes
MYSQLINNODB=$(awk '{size = $1 / 1024 / 1024 ; print size " M"} ' <<< "$INNODBVALUE")


#-------------------------------MYISAM KEY BUFFER SIZE VARIABLES-------------------------------#


# Search the $MYSQLCONF variable for the InnoDB Buufer Pool variable. This is just goign to identify if it's there or not
MYISAMPRESENT=$(awk '/key_buffer/' <<< "$MYSQLCONF")

# This will take the value that's assigned to the InnoDB Buffer Pool (should it exist) and store the value
MYISAMVALUE=$(awk -F"=" '/key_buffer/ {print $2}'i <<< "$MYSQLCONF")

# Grabs just the value for the buffer pool
MYISAMVALNUMREGEX="(([0-9]+)).*$"
[[ $MYISAMVALUE =~ $MYISAMVALNUMREGEX ]] &&
MYISAMNUMVALUE=${BASH_REMATCH[1]} # Only the value

#Grabs just the alpha character denoting the memory denomination
MYISAMVALALPHREGEX="([A-Za-z]).*$"
[[ $MYISAMVALUE =~ $MYISAMVALALPHREGEX ]] &&
MYISAMDENOM=${BASH_REMATCH[1]} # The memory denomination being used

# This calculates what the value would be in MiB since it may be written out in bytes
MYSQLMYISAM=$(awk '{size = $1 / 1024 / 1024 ; print size " M"} ' <<< "$MYISAMVALUE")


#-----------------------------------MEMORY RELATED VARIABLES-----------------------------------#


# This captures that information we'll use to display the total GB of memory on the system
MEMINFOGB=$(free -g)

# This captures the rest of the memory related information we'll pull from
MEMINFOMB=$(cat /proc/meminfo)

# This captures the total # of GBs on a system
TOTALMEMMB=$(awk '/Mem:/ {print $2}' <<< "$MEMINFOGB")

# Adds +1 since the actual value displayed does not round up. I'm basically doing the rounding for it
TOTALMEMGB=$(($TOTALMEMMB+1))

# The following capture the total amount of memory, the fre amount and calculates the amount used, all in MB
MEMTOTAL=$(awk -F":" '/MemTotal/{ printf "%.0f", $2/1024 ; exit}' <<< "$MEMINFOMB")
MEMFREE=$(awk -F":" '/MemFree/{ printf "%.0f", $2/1024 ; exit}' <<< "$MEMINFOMB")
MEMUSED=$(($MEMTOTAL-$MEMFREE))

# In order to get an accurate value of how much memory is actually free we need to know how much is being used for buffers / cache
BUFFERS=$(awk -F":" '/Buffers/{ printf "%.0f", $2/1024 ; exit}' <<< "$MEMINFOMB")
CACHED=$(awk -F":" '/Cached/{ printf "%.0f", $2/1024 ; exit}' <<< "$MEMINFOMB")
BUFFERCACHETOTAL=$(($BUFFERS+$CACHED))

# Determine the actual amount of free memory (since buffer / cache usage gives way to application usage when requested)
MEMTRUEFREE=$(($MEMFREE+$BUFFERCACHETOTAL))

# Calculates the total, free, and actually used swap values
SWAPTOTAL=$(awk -F":" '/SwapTotal/{ printf "%.0f", $2/1024 ; exit}' <<< "$MEMINFOMB")
SWAPFREE=$(awk -F":" '/SwapFree/ { printf "%.0f", $2/1024 ; exit}' <<< "$MEMINFOMB")
SWAPUSED=$(($SWAPTOTAL-$SWAPFREE))

# Calculates the total memory currently being used by Apache
APACHEMEM=$(ps -ylC httpd | awk '{x += $8;y += 1} END {print x/1024}' | cut -d "." -f1)

# Calculates the total memory the kernel itself is using
KERNELMEM=$(grep Slab /proc/meminfo | awk '{x += $2} END {print x/1024}' | cut -d "." -f1)


#-----------------------------MYSQL DATABASE DETAIL(s) VARIABLES ------------------------------#

# Captures the size of all InnoDB tables
INNODBSIZE=$(mysql -e "SELECT engine, count(*) tables, concat(round(sum(table_rows)/1000000,2),'M') rows, concat(round(sum(data_length)/(1024*1024*1024),2),'G') data, concat(round(sum(index_length)/(1024*1024*1024),2),'G') idx, concat(round(sum(data_length+index_length)/(1024*1024*1024),2),'G') total_size, round(sum(index_length)/sum(data_length),2) idxfrac FROM information_schema.TABLES GROUP BY engine ORDER BY sum(data_length+index_length) DESC LIMIT 10;" | egrep '(InnoDB)' | cut -f6)

# Captures the size of all MyISAM tables
MYISAMSIZE=$(mysql -e "SELECT engine, count(*) tables, concat(round(sum(table_rows)/1000000,2),'M') rows, concat(round(sum(data_length)/(1024*1024*1024),2),'G') data, concat(round(sum(index_length)/(1024*1024*1024),2),'G') idx, concat(round(sum(data_length+index_length)/(1024*1024*1024),2),'G') total_size, round(sum(index_length)/sum(data_length),2) idxfrac FROM information_schema.TABLES GROUP BY engine ORDER BY sum(data_length+index_length) DESC LIMIT 10;" | egrep '(MyISAM)' | cut -f6)

# Captures the size of the InnoDB cache
INNODBCACHE=$(mysql -e "SELECT FLOOR(SUM(data_length+index_length)/POWER(1024,2)) InnoDBSizeMB FROM information_schema.tables WHERE engine='InnoDB';"| grep -v InnoDBSizeMB)

# Captures the size of the MyISAM cache
MYISAMCACHE=$(mysql -e "SELECT FLOOR(SUM(index_length)/POWER(1024,2)) IndexSizesMB FROM information_schema.tables WHERE engine='MyISAM' AND table_schema NOT IN ('information_schema','performance_schema','mysql');"| grep -v IndexSizesMB)

# Counts and captures the total number of InnoDB tables
TOTALINNODB=$(mysql -e "SELECT concat(TABLE_SCHEMA, '.', TABLE_NAME) FROM information_schema.tables WHERE engine = 'InnoDB'" | wc -l)

# Counts and captures the total number of MyISAM tables
TOTALMYISAM=$(mysql -e "SELECT concat(TABLE_SCHEMA, '.', TABLE_NAME) FROM information_schema.tables WHERE engine = 'MyISAM'" | wc -l)

# Calculates what the recommended InnoDB Buffer Pool size should be exactly (no room for growth)
INNODBREC=$(mysql -e "SELECT CONCAT(ROUND(KBS/POWER(1024, IF(PowerOf1024<0,0,IF(PowerOf1024>3,0,PowerOf1024)))+0.49999), SUBSTR(' KMG',IF(PowerOf1024<0,0, IF(PowerOf1024>3,0,PowerOf1024))+1,1)) recommended_innodb_buffer_pool_size FROM (SELECT SUM(data_length+index_length) KBS FROM information_schema.tables WHERE engine='InnoDB') A, (SELECT 2 PowerOf1024) B;" | grep -v recommended_innodb_buffer_pool_size)

# Calculates what the recommended MyISAM Key Buffer size should be exactly (no room for growth)
MYISAMREC=$(mysql -e "SELECT CONCAT(ROUND(KBS/POWER(1024, IF(PowerOf1024<0,0,IF(PowerOf1024>3,0,PowerOf1024)))+0.4999), SUBSTR(' KMG',IF(PowerOf1024<0,0, IF(PowerOf1024>3,0,PowerOf1024))+1,1)) recommended_key_buffer_size FROM (SELECT LEAST(POWER(2,32),KBS1) KBS FROM (SELECT SUM(index_length) KBS1 FROM information_schema.tables WHERE engine='MyISAM' AND table_schema NOT IN ('information_schema','mysql')) AA ) A, (SELECT 2 PowerOf1024) B;" | grep -v recommended_key_buffer_size)

#----------------------------------------------------------------------------------------------#
#                                     END SCRIPT VARIABLES                                     #
################################################################################################




# Clear the screen
clear




################################################################################################
#                                        BEGIN HEADER                                          #
#----------------------------------------------------------------------------------------------#

echo " ${LIGHT} __  __       ____   ___  _          "
echo " |  \/  |_   _/ ___| / _ \| |         "
echo " | |\/| | | | \___ \| | | | |         "
echo " | |  | | |_| |___) | |_| | |___      "
echo " |_|  |_|\__, |____/ \__\_\_____|  ${RESET}   "
echo " ${DARK}   ____${LIGHT} |___/${RESET}${DARK}_       ${RESET} _  __     "
echo " ${DARK}  / ___|__ _| | ___  ${RESET}(_)/ /     "
echo " ${DARK} | |   / _\` | |/ __|${RESET}   / /      "
echo " ${DARK} | |__| (_| | | (__  ${RESET} / /_ v$VERSION "     
echo " ${DARK}  \____\__,_|_|\___| ${RESET}/_/(_)     "



################################################################################################
#                                      BEGIN INFO DISPLAY                                      #
#----------------------------------------------------------------------------------------------#

echo

echo -n "------------\ ${MEMORYINFO}${UNDERLINE}MEMORY INFO${RESET} \-------------------------------" 

echo
echo

echo "${MEMORYINFO}Total System Memory:${RESET}" $MEMTOTAL
echo "${MEMORYINFO}Apache Memory Usage:${RESET}" $APACHEMEM
echo "${MEMORYINFO}Kernel Memory Usage:${RESET}" $KERNELMEM
echo "${MEMORYINFO}Current Memory Free:${RESET}" $MEMTRUEFREE

echo

echo -n "------------\ ${MYSQLINFO}${UNDERLINE}MYSQL INFO${RESET} \--------------------------------"

echo
echo

echo "${MYSQLINFO}Version In Use:${RESET}" $MYSQLENTIREVERSION

echo

#if (( $(echo "$MYSQLMAJORVERSION.$MYSQLMINORVERSION < $CURRENT" | bc -l) )); then
#	echo "$(tput setab 1)$(tput bold ; tput setaf 15) You do NOT have the latest version of MySQL $(tput sgr0)";echo
#fi

echo "${MYSQLINFO}${UNDERLINE}InnoDB Elements${RESET}"
echo "${MYSQLINFO}Overall Size #:${RESET}" $INNODBSIZE
echo "${MYSQLINFO}Total Table(s):${RESET}" $TOTALINNODB
echo "${MYSQLINFO}Entire Cache #:${RESET}" $INNODBCACHE M
#echo "${MYSQLINFO}Buffer(s) Pool: ${RESET}" $MYSQLINNODB
if [[ "$INNODBPRESENT" == "" ]];then

        echo "${MYSQLINFO}Buffer(s) Pool:${RESET} 128 MB (default)"

elif [[ $INNODBVALUE == *M ]] || [[ $INNODBVALUE == *G ]]; then

        echo "${MYSQLINFO}Buffer(s) Pool:${RESET} $INNODBNUMVALUE $INNODBDENOM"

else

        echo "${MYSQLINFO}Buffer(s) Pool:${RESET} $MYSQLINNODB"

fi

echo

echo "${MYSQLINFO}${UNDERLINE}MyISAM Elements${RESET}"
echo "${MYSQLINFO}Overall Size #:${RESET}" $MYISAMSIZE
echo "${MYSQLINFO}Total Table(s):${RESET}" $TOTALMYISAM
echo "${MYSQLINFO}Entire Cache #:${RESET}" $MYISAMCACHE M
#echo "${MYSQLINFO}Buffer(s) Pool: ${RESET}" $MYSQLMYISAM
if [[ "$MYISAMPRESENT" == "" ]];then

        echo "${MYSQLINFO}Buffer(s) Pool:${RESET} 8 M (default)"

elif [[ $MYISAMVALUE == *M ]] || [[ $MYISAMVALUE == *G ]];then

        echo "${MYSQLINFO}Buffer(s) Pool:${RESET} $MYISAMNUMVALUE $MYISAMDENOM"

else

        echo "${MYSQLINFO}Buffer(s) Pool:${RESET} $MYSQLMYISAM"

fi

echo

echo -n "------------\ ${RECOMMENDATIONS}${UNDERLINE}RECOMMENDATIONS${RESET} \---------------------------"

echo
echo

echo  "${RECOMMENDATIONS}Alter InnoDB Buffer Pool Size to be: ${RESET}" $INNODBREC
echo  "${RECOMMENDATIONS}Change MyISAM Key Buffer Size to be: ${RESET}" $MYISAMREC

echo

#if (( $(echo "$present < $current" | bc -l) )); then
#	echo "$(tput setaf 42)Recommend Upgrading MySQL to version: $(tput sgr0)"$current; echo
#else
#	echo
#fi
