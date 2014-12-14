#!/bin/bash
#
#  AUTHOR: michael mcdonald
# CONTACT: michael@liquidweb.com
# VERSION: 1.0
# PURPOSE: this will make some recommendations on tuning your MySQL
#          configuration based on your current database and memory usage

export present=`mysql -V | cut -d " " -f6 | sed 's/,$//' | cut -d "." -f1,2`
export current="5.6"

poolsize=`grep innodb_buffer_pool_size /etc/my.cnf | cut -d "=" -f2`
apachemem=`ps -ylC httpd | awk '{x += $8;y += 1} END {print x/1024}' | cut -d "." -f1`
kernelmem=`grep Slab /proc/meminfo | awk '{x += $2} END {print x/1024}' | cut -d "." -f1`
innodbsize=`mysql -e "SELECT engine, count(*) tables, concat(round(sum(table_rows)/1000000,2),'M') rows, concat(round(sum(data_length)/(1024*1024*1024),2),'G') data, concat(round(sum(index_length)/(1024*1024*1024),2),'G') idx, concat(round(sum(data_length+index_length)/(1024*1024*1024),2),'G') total_size, round(sum(index_length)/sum(data_length),2) idxfrac FROM information_schema.TABLES GROUP BY engine ORDER BY sum(data_length+index_length) DESC LIMIT 10;" | egrep '(InnoDB)' | cut -f6;`
myisamsize=`mysql -e "SELECT engine, count(*) tables, concat(round(sum(table_rows)/1000000,2),'M') rows, concat(round(sum(data_length)/(1024*1024*1024),2),'G') data, concat(round(sum(index_length)/(1024*1024*1024),2),'G') idx, concat(round(sum(data_length+index_length)/(1024*1024*1024),2),'G') total_size, round(sum(index_length)/sum(data_length),2) idxfrac FROM information_schema.TABLES GROUP BY engine ORDER BY sum(data_length+index_length) DESC LIMIT 10;" | egrep '(MyISAM)' | cut -f6;`
innodbcache=`mysql -e "SELECT FLOOR(SUM(data_length+index_length)/POWER(1024,2)) InnoDBSizeMB
FROM information_schema.tables WHERE engine='InnoDB';"| grep -v InnoDBSizeMB`
myisamcache=`mysql -e "SELECT FLOOR(SUM(index_length)/POWER(1024,2)) IndexSizesMB
FROM information_schema.tables WHERE engine='MyISAM' AND
table_schema NOT IN ('information_schema','performance_schema','mysql');"| grep -v IndexSizesMB`
totalinnodb=`mysql -e "SELECT concat(TABLE_SCHEMA, '.', TABLE_NAME) FROM information_schema.tables WHERE engine = 'InnoDB'" | wc -l`
totalmyisam=`mysql -e "SELECT concat(TABLE_SCHEMA, '.', TABLE_NAME) FROM information_schema.tables WHERE engine = 'MyISAM'" | wc -l`


     echo;echo -n "$(tput setaf 2)MySQL Recommendations for `hostname`$(tput sgr0)";echo;echo

    echo -n "|---  $(tput setaf 180)SYSTEM MEMORY INFO$(tput sgr0)  ---|"; echo;echo;


        echo "$(tput setaf 180)Total System Memory:$(tput sgr0)" `free -m | grep Mem | awk '{print $2}'`M;


        echo "$(tput setaf 180)Apache Memory Usage: $(tput sgr0)"$((apachemem))M;


        echo "$(tput setaf 180)Kernel Memory Usage: $(tput sgr0)"$((kernelmem))M;

    echo; echo -n "|---  $(tput setaf 4)CURRENT MYSQL INFO$(tput sgr0)  ---|"; echo;echo;

        echo -n "$(tput setaf 4)MySQL Version:  $(tput sgr0)"; mysql -V | cut -d " " -f6 | sed 's/,$//';

    echo

        if (( $(echo "$present < $current" | bc -l) )); then

            echo "$(tput setab 1)$(tput bold ; tput setaf 15) You do NOT have the latest version of MySQL $(tput sgr0)";echo

fi

        echo "$(tput setaf 4)# of MyISAM Tables: $(tput sgr0)"$totalmyisam;

        echo "$(tput setaf 4) MyISAM Total Size: $(tput sgr0)"$myisamsize;

        echo "$(tput setaf 4) MyISAM Cache Size: $(tput sgr0)"$((myisamcache))M;

    echo

        echo "$(tput setaf 4)# of InnoDB Tables: $(tput sgr0)"$totalinnodb;

        echo "$(tput setaf 4) InnoDB Total Size: $(tput sgr0)"$innodbsize;

        echo "$(tput setaf 4) InnoDB Cache Size: $(tput sgr0)"$((innodbcache))M;

   # echo
   #
   # if [[ $poolsize == *M ]] || [[ $poolsize == *G ]]
   #
   # then
   #
   #    echo "$(tput setaf 4)Current InnoDB Buffer Pool Size: $(tput sgr0)$poolsize";
   #
   # else
   #
   #     echo "$(tput setaf 4)Current InnoDB Buffer Pool Size: $(tput sgr0)"$((poolsize / 1048576))M;

    echo; echo -n "|---    $(tput setaf 42)RECOMMENDATION$(tput sgr0)    ---|"; echo;echo;

        echo -n "$(tput setaf 42)Recommended InnoDB Buffer Pool Size: $(tput sgr0)"; mysql -e "SELECT CONCAT(ROUND(KBS/POWER(1024, IF(PowerOf1024<0,0,IF(PowerOf1024>3,0,PowerOf1024)))+0.49999), SUBSTR(' KMG',IF(PowerOf1024<0,0, IF(PowerOf1024>3,0,PowerOf1024))+1,1)) recommended_innodb_buffer_pool_size FROM (SELECT SUM(data_length+index_length) KBS FROM information_schema.tables WHERE engine='InnoDB') A, (SELECT 2 PowerOf1024) B;" | grep -v recommended_innodb_buffer_pool_size ;

        echo -n "$(tput setaf 42)Recommended MyISAM Key Buffer Size: $(tput sgr0)"; mysql -e "SELECT CONCAT(ROUND(KBS/POWER(1024, IF(PowerOf1024<0,0,IF(PowerOf1024>3,0,PowerOf1024)))+0.4999), SUBSTR(' KMG',IF(PowerOf1024<0,0, IF(PowerOf1024>3,0,PowerOf1024))+1,1)) recommended_key_buffer_size FROM (SELECT LEAST(POWER(2,32),KBS1) KBS FROM (SELECT SUM(index_length) KBS1 FROM information_schema.tables WHERE engine='MyISAM' AND table_schema NOT IN ('information_schema','mysql')) AA ) A, (SELECT 2 PowerOf1024) B;" | grep -v recommended_key_buffer_size ;

        if (( $(echo "$present < $current" | bc -l) )); then

            echo "$(tput setaf 42)Recommend Upgrading MySQL to version: $(tput sgr0)"$current; echo;

        else

            echo;

fi
