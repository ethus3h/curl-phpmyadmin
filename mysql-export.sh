#!/usr/bin/env bash

#set -x

# Documentation: This saves dumps of your Database using CURL and connecting to
# phpMyAdmin (via HTTPS), keeping the 10 latest backups by default
#
# Tested on phpMyAdmin 3.5.1 and 3.4.10.1
#
# For those interested in debugging/adapting this script, the firefox
# add-on LiveHttpHeaders is a very interesting extension to debug HTTP
# transactions and guess what's needed to develop such a CURL-based
# script.
#
# Arguments: mysql-export.sh [-h|--help] [--stdout] [--tables=<table_name>,<table_name>,...] 
#                            [--compression=none|gzip|bzip2|zip] [--add-drop] 
#                            [--apache-user=<apache_http_user>] [--apache-password=<apache_http_password>] 
#                            [--phpmyadmin-user=<phpmyadmin_user>] [--phpmyadmin-password=<phpmyadmin_password>] 
#                            [--database=<database>] [--host=<phpmyadmin_host>] [--use-keychain] 
#                            -- [curl_options]
#        -h, --help: Print help
#        --stdout: Write SQL (gzipped) in stdout
#        --tables=<T1>,<T2>,..: Export only particular tables
#        --compression: Turn compression off (none) or use gzip, bzip2 (default) or zip
#        --add-drop: add DROP TABLE IF EXISTS to every exporting table
#        --apache-user=<apache_http_user>: Apache HTTP autorization user
#        --apache-password=<apache_http_password>: Apache HTTP autorization password 
#        --phpmyadmin-user=<phpmyadmin_user>: PhpMyAdmin user *
#        --phpmyadmin-password=<phpmyadmin_password>: PhpMyAdmin password *
#        --database=<database>: Database to be exported *
#        --host=<phpmyadmin_host>: PhpMyAdmin host *
#        --use-keychain: Use Mac OS X keychain to get passwords from. 
#          In that case --apache-password and --phpmyadmin-password will be used 
#          as account name for search in Mac Os X keychain. 
# 
#        * You need to set at least those parameters on the command line or in the script
# 
#        --  [curl_options] Options may be passed to every curl command (e.g. http_proxy)
# 
#  Common uses: mysql-export.sh --tables=hotel_content_provider --add-drop --database=hs --stdout --use-keychain --apache-user=betatester --phpmyadmin-user=hs --apache-password=www.example.com\ \(me\) --phpmyadmin-password=phpmyadmin.example.com --host=https://www.example.com/phpmyadmin | gunzip | mysql -u root -p testtable
# 
#     This exports and imports on the fly into local db
# 
# Please adapt these values :

MKTEMP=mktemp # 'mktemp' or 'tempfile'
TMP_FOLDER=/tmp
COMPRESSION=bzip2
USE_KEYCHAIN=0
DEBUG=0

## following values will be overwritten by command line arguments
STDOUT=
DB_TABLES=
ADD_DROP=0
APACHE_USER=
APACHE_PASSWD=
PHPMYADMIN_USER=
PHPMYADMIN_PASSWD=
DATABASE=
REMOTE_HOST=
# End of customisations


## debugging function
function decho {
    [[ "$DEBUG" -eq 1 ]] && echo "$@"
}

function usage
{
        cat << EOF
Arguments: mysql-export.sh [-h|--help] [--stdout] [--tables=<table_name>,<table_name>,...] 
                           [--compression=none|gzip|bzip2|zip] [--add-drop] 
                           [--apache-user=<apache_http_user>] [--apache-password=<apache_http_password>] 
                           [--phpmyadmin-user=<phpmyadmin_user>] [--phpmyadmin-password=<phpmyadmin_password>] 
                           [--database=<database>] [--host=<phpmyadmin_host>] [--use-keychain] 
                           -- [curl_options]
       -h, --help: Print help
       --stdout: Write SQL (gzipped) in stdout
       --tables=<T1>,<T2>,..: Export only particular tables
       --compression: Turn compression off (none) or use gzip, bzip2 (default) or zip
       --add-drop: add DROP TABLE IF EXISTS to every exporting table
       --apache-user=<apache_http_user>: Apache HTTP autorization user
       --apache-password=<apache_http_password>: Apache HTTP autorization password 
       --phpmyadmin-user=<phpmyadmin_user>: PhpMyAdmin user *
       --phpmyadmin-password=<phpmyadmin_password>: PhpMyAdmin password *
       --database=<database>: Database to be exported *
       --host=<phpmyadmin_host>: PhpMyAdmin host *
       --use-keychain: Use Mac OS X keychain to get passwords from. 
         In that case --apache-password and --phpmyadmin-password will be used 
         as account name for search in Mac Os X keychain. 

       * You need to set at least those parameters on the command line or in the script

       --  [curl_options] Options may be passed to every curl command (e.g. http_proxy)

 Common uses: mysql-export.sh --tables=hotel_content_provider --add-drop --database=hs --stdout --use-keychain --apache-user=betatester --phpmyadmin-user=hs --apache-password=www.example.com\ \(me\) --phpmyadmin-password=phpmyadmin.example.com --host=https://www.example.com/phpmyadmin | gunzip | mysql -u root -p testtable

    This exports and imports on the fly into local db
EOF
}

curloptions=0
curlopts=""
for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
        curloptions=1
    elif [[ "$curloptions" -eq 1 ]]; then
        curlopts+="$arg "
    elif [[ $arg == '--stdout' ]]; then
        STDOUT=1
    elif [[ "$arg" =~ '--tables' ]]; then
        DB_TABLES="$arg"
    elif [[ "$arg" =~ '--compression' ]]; then
        COMPRESSION="${arg:14}"
    elif [[ "$arg" == '--add-drop' ]]; then
        ADD_DROP=1
    elif [[ "$arg" =~ '--apache-user' ]]; then
        APACHE_USER="${arg:14}"
    elif [[ "$arg" =~ '--apache-password' ]]; then
        APACHE_PASSWD="${arg:18}"
    elif [[ "$arg" =~ '--phpmyadmin-user' ]]; then
        PHPMYADMIN_USER="${arg:18}"
    elif [[ "$arg" =~ '--phpmyadmin-password' ]]; then
        PHPMYADMIN_PASSWD="${arg:22}"
    elif [[ "$arg" =~ '--database' ]]; then
        DATABASE="${arg:11}"
    elif [[ "$arg" =~ '--host' ]]; then
        REMOTE_HOST="${arg:7}"
    elif [[ "$arg" == '--use-keychain' ]]; then
        USE_KEYCHAIN=1
    else
        usage
        exit 0        
    fi
done
curlopts+="-s -k -L"
decho "Curl options: $curlopts"

# is APACHE auth really necessary?
#[ -z "$APACHE_USER" -o -z "$APACHE_PASSWD" ] && usage && exit 1
#if [ -z "$PHPMYADMIN_USER" -o -z "$PHPMYADMIN_PASSWD" ];
if [[ -z "$DATABASE" || -z "$REMOTE_HOST" ]]; then 
    usage
    exit 1
fi

## not tested (01.03.13)
if [[ "$USE_KEYCHAIN" -eq 1 ]]; then
    APACHE_PASSWD=`security 2>&1 >/dev/null find-internet-password -gs $APACHE_PASSWD | sed -e 's/password: "\(.*\)"/\1/g'`
    PHPMYADMIN_PASSWD=`security 2>&1 >/dev/null find-internet-password -g -l $PHPMYADMIN_PASSWD | sed -e 's/password: "\(.*\)"/\1/g'`
fi

## which mktemp to use
mkdir -p "$TMP_FOLDER" || exit 1
if [[ "$MKTEMP" == "mktemp" ]]; then
    result=$(`which mktemp` "$TMP_FOLDER/phpmyadmin_export.XXXXXX.tmp")
    decho TEMP: "$result"
fi
if [[ "MKTEMP" == "tempfile" ]]; then
    result=$(`which tempfile` -d "$TMP_FOLDER")
    decho TEMP: "$result"
fi


###############################################################
#
# First login and fetch the cookie which will be used later
#
###############################################################

apache_auth_params="--anyauth -u$APACHE_USER:$APACHE_PASSWD"

curl "$curlopts" -D "$TMP_FOLDER/curl.headers" -c "$TMP_FOLDER/cookies.txt" "$apache_auth_params" "$REMOTE_HOST/index.php" > "$result"
#    token=$(grep 'token\ =' $result | sed "s/.*token\ =\ '//;s/';$//" )

    token="$(grep link "$result" | grep 'phpmyadmin.css.php' | grep token | sed "s/^.*token=//" | sed "s/[&'].*//" )"
    cookie="$(cat "$TMP_FOLDER/cookies.txt" | cut  -f 6-7 | grep phpMyAdmin | cut -f 2)"

entry_params="-d \"phpMyAdmin=$cookie&pma_username=$PHPMYADMIN_USER&pma_password=$PHPMYADMIN_PASSWD&server=1&lang=en-utf-8&convcharset=utf-8&collation_connection=utf8_general_ci&token=$token&input_go=Go\""
decho Apache login: "$apache_auth_params"
decho PhpMyadmin login: "$entry_params"
decho Token: "$token"
decho Cookie: "$cookie"
## Try to log in with PhpMyAdmin username and password showing errors if it fails
curl "$curlopts" -S -D "$TMP_FOLDER/curl.headers" -b "$TMP_FOLDER/cookies.txt" -c "$TMP_FOLDER/cookies.txt" "$apache_auth_params" "$entry_params" "$REMOTE_HOST/index.php" > "$result"
## did it fail?
if [[ $? -ne 0 ]]; then
    echo "Curl error on: curl $curlopts -S -D $TMP_FOLDER/curl.headers -b $TMP_FOLDER/cookies.txt -c $TMP_FOLDER/cookies.txt $apache_auth_params $entry_params $REMOTE_HOST/index.php > $result" >&2
    exit 1
fi
## Was the HTTP request unsuccessful?
grep -q "HTTP/1.1 200 OK" "$TMP_FOLDER/curl.headers"
if [[ $? -ne 0 ]]; then
    echo -n "Error: couldn't login to phpMyadmin on $REMOTE_HOST/index.php" >&2
    grep "HTTP/1.1 " "$TMP_FOLDER/curl.headers" >&2
    exit 1
fi

## prepare the post-parameters
post_params="token=${token}"
## later: post_params+="&export_type=server"
post_params+="&export_method=quick"
post_params+="&quick_or_custom=custom"
## later: post_params+="&db_select%5B%5D=$DATABASE"
post_params+="&output_format=sendit"
## later: post_params+="&filename_template=%40SERVER%40" 
post_params+="&remember_template=on"
post_params+="&charset_of_file=utf-8"
## later: post_params+="&compression=none"
post_params+="&what=sql"
post_params+="&codegen_structure_or_data=data"
post_params+="&codegen_format=0"
post_params+="&csv_separator=%2C"
post_params+="&csv_enclosed=%22"
post_params+="&csv_escaped=%22"
post_params+="&csv_terminated=AUTO"
post_params+="&csv_null=NULL"
post_params+="&csv_structure_or_data=data"
post_params+="&excel_null=NULL"
post_params+="&excel_edition=win"
post_params+="&excel_structure_or_data=data"
post_params+="&htmlword_structure_or_data=structure_and_data"
post_params+="&htmlword_null=NULL"
post_params+="&json_structure_or_data=data"
post_params+="&latex_caption=something"
post_params+="&latex_structure_or_data=structure_and_data"
post_params+="&latex_structure_caption=Structure+of+table+%40TABLE%40"
post_params+="&latex_structure_continued_caption=Structure+of+table+%40TABLE%40+%28continued%29"
post_params+="&latex_structure_label=tab%3A%40TABLE%40-structure"
post_params+="&latex_comments=something"
post_params+="&latex_columns=something"
post_params+="&latex_data_caption=Content+of+table+%40TABLE%40"
post_params+="&latex_data_continued_caption=Content+of+table+%40TABLE%40+%28continued%29"
post_params+="&latex_data_label=tab%3A%40TABLE%40-data"
post_params+="&latex_null=%5Ctextit%7BNULL%7D"
post_params+="&mediawiki_structure_or_data=data"
post_params+="&ods_null=NULL"
post_params+="&ods_structure_or_data=data"
post_params+="&odt_structure_or_data=structure_and_data"
post_params+="&odt_comments=something"
post_params+="&odt_columns=something"
post_params+="&odt_null=NULL"
post_params+="&pdf_report_title="
post_params+="&pdf_structure_or_data=data"
post_params+="&php_array_structure_or_data=data"
post_params+="&sql_include_comments=something"
post_params+="&sql_header_comment="
post_params+="&sql_compatibility=NONE"
post_params+="&sql_structure_or_data=structure_and_data"
post_params+="&sql_procedure_function=something"
post_params+="&sql_create_table_statements=something"
post_params+="&sql_if_not_exists=something"
post_params+="&sql_auto_increment=something"
post_params+="&sql_backquotes=something"
post_params+="&sql_type=INSERT"
post_params+="&sql_insert_syntax=both"
post_params+="&sql_max_query_size=50000"
post_params+="&sql_hex_for_blob=something"
post_params+="&sql_utc_time=something"
post_params+="&texytext_structure_or_data=structure_and_data"
post_params+="&texytext_null=NULL"
post_params+="&yaml_structure_or_data=data"

if [[ "$ADD_DROP" -eq 1 ]];  then
    post_params+="&sql_drop_table=something"
fi    

target="$(echo "$REMOTE_HOST" | sed 's@^http[s]://@@;s@/.*@@')_${DATABASE}_$(date +%Y%m%d%H%M).sql"

post_params+="&compression=$COMPRESSION"
case "$COMPRESSION" in 
    gzip)
        target+=".gz"
        ;;
    bzip2)
        target+=".bz2"
        ;;
    zip)
        target+=".zip"
        ;;
    none)
        ;;
    *)
        target+="err.compression"
        ;;
esac

decho Database: $DATABASE
if [  -n "$DB_TABLES" ] ; then
    DB_TABLES=${DB_TABLES/=/table_select%5B%5D=}
    DB_TABLES=${DB_TABLES//,/&table_select%5B%5D=}
    DB_TABLES=${DB_TABLES:8}
    decho Tables: $DB_TABLES
    
    post_params+="&db=$DATABASE"
    post_params+="&export_type=database"
    post_params+="&$DB_TABLES"
    post_params+="&filename_template=%40DATABASE%40"

    post_params+="&xml_structure_or_data=data"
    post_params+="&xml_export_functions=something"
    post_params+="&xml_export_procedures=something"
    post_params+="&xml_export_tables=something"
    post_params+="&xml_export_triggers=something"
    post_params+="&xml_export_views=something"
    post_params+="&xml_export_contents=something"
else
    post_params+="&export_type=server"
    post_params+="&db_select%5B%5D=$DATABASE"
    post_params+="&filename_template=%40SERVER%40" 
fi

## the important curl command, either output to stdout additionally
if [[ -n "$STDOUT" ]]; then
decho "    Exportcommand: curl $curlopts -g -S -D $TMP_FOLDER/curl.headers -b $TMP_FOLDER/cookies.txt $apache_auth_params -d "$post_params" $REMOTE_HOST/export.php"
    curl $curlopts -g -S -D $TMP_FOLDER/curl.headers -b $TMP_FOLDER/cookies.txt $apache_auth_params -d "$post_params" $REMOTE_HOST/export.php
else
decho " Exportcommand: curl $curlopts -g -S -O -D $TMP_FOLDER/curl.headers -b $TMP_FOLDER/cookies.txt $apache_auth_params -d "$post_params" $REMOTE_HOST/export.php"    
    curl $curlopts -g -S -O -D $TMP_FOLDER/curl.headers -b $TMP_FOLDER/cookies.txt $apache_auth_params -d "$post_params" $REMOTE_HOST/export.php

        ##  check if there was an attachement
    grep -q "Content-Disposition: attachment" $TMP_FOLDER/curl.headers
    if [[ $? -eq 0 ]]; then
        mv export.php $target
        echo "Saved: $target"
    else
        echo "Error: No attachment. Something went wrong. See export.php"
        exit 1
    fi
fi

# remove the old backups and keep the 10 younger ones.
#ls -1 backup_mysql_*${database}_*.gz | sort -u | head -n-10 | xargs -r rm -v
rm -f $result
rm -f $TMP_FOLDER/curl.headers
rm -f $TMP_FOLDER/cookies.txt
