# compiz-plugins-community

This package is part of Wreathe, and is maintained by the Ember project.

Learn about Wreathe at the Ember Web site: http://futuramerlin.com/ancillary/wreathe/

Please report any issues you find with this repository to the Ember project's issue tracker at http://futuramerlin.com/issue-tracker/.

## Usage

Export MySQL data from phpmyadmin using curl.

```
mysql-export.sh [-h|--help] [--stdout] [--tables=<table_name>,<table_name>,...] 
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
```

### Common usage example

```
mysql-export.sh --tables=hotel_content_provider --add-drop --database=hs --stdout --use-keychain --apache-user=betatester --phpmyadmin-user=hs --apache-password=www.example.com\ \(me\) --phpmyadmin-password=phpmyadmin.example.com --host=https://www.example.com/phpmyadmin | gunzip | mysql -u root -p testtable
```

This exports and imports on the fly into local db.
