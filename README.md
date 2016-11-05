#						watchdogocr


##  What is it?
##  -----------
A "watchdog" script running in background on linux servers and 
scanning pdf files in folder. New files cut by pages and push into queue.
All pages ocr and every page save in to database (MSSQL) in xml, txt, json, html formats.

### How to install

	1. You need next software: pdf2txt.py, pdfseparate, pypdfocr, FreeTDS odbc drivers
	
	2. How to setup your odbc connection:
```
$ cat  /home/directware/tmp/odbc.temp/odbc.temp
[data]
Driver = FreeTDS
Servername = data
Port = 1433
[MSSQLTestServer]
Driver = FreeTDS
Description = data.ZZZZZZZ.biz
Trace = No
Server = data.ZZZZZZZ.biz
Port = 1433
Database = Maintenance	
$ odbcinst -i -s -f /home/directware/tmp/odbc.temp
```

	3.  Structure of working directories:
```
/home/directware/watchdogocr
/home/directware/watchdogocr/watchdogocr_common.pm
/home/directware/watchdogocr/watchdogocr_file.pl
/home/directware/watchdogocr/do_sql.pl
/home/directware/watchdogocr/check_data.pl
/home/directware/watchdogocr/etc
/home/directware/watchdogocr/var
/home/directware/watchdogocr/var/tmp
/home/directware/watchdogocr/var/log
/home/directware/watchdogocr/watchdogocr.pl
/home/directware/watchdogocr/export_data.pl
/home/directware/docs/in
/home/directware/docs/in/running
/home/directware/docs/in/failed
/home/directware/docs/in/process
/home/directware/docs/in/pages
/home/directware/docs/in/finished
```

	4. Create table in your database:
```
CREATE TABLE OCRFiles ( ID int IDENTITY(1,1) PRIMARY KEY, ffilename varchar( 255 ) not null , fpages int not null, EntryTime DATETIME NOT NULL DEFAULT GETDATE() ) ;
CREATE TABLE OCREntries ( ID int IDENTITY(1,1) PRIMARY KEY, ffilename varchar( 255 ) not null , fpage int not null, EntryTime DATETIME NOT NULL DEFAULT GETDATE(), 
ftext varchar, fxml varchar, fhtml varchar, fjson varchar, ocrfiles_id int ) ;
```



	5. Edit the _watchdogocr_common.pm_ with your prefferences:
		+  $SCAN_DIR - dirs you plane to scan
		+  $CHECK_FILE_MASK - filemask for your pdf files

	6. Install required perl modules: DBI, DBD::ODBC, XML::Simple, JSON::XS
   

### How to run
There three ways to run:
   1. From command line. Usualy for testing resone. Simple run ```/home/directware/watchdogocr/watchdogocr.pl```
   2. From crontab. Add next line to your crontab with ```crontab -e``` command:
   ```
*	*	*	*	*	/home/directware/watchdogocr/watchdogocr.pl >/dev/null 2>&1
   ```
   3. From command line as daemon. Run ```/home/directware/watchdogocr/watchdogocr.pl --daemon >/dev/null 2>&1 &```
   
Put your pdf files into directory `/home/directware/docs/in`. After this watchdogocr will start processing your files during 30 seconds.
Processing files moved into `/home/directware/docs/in/process`, faled files moved into `/home/directware/docs/in/failed`. 
All logs saved into `/home/directware/watchdogocr/var/log` .
   
### How to get info from database   

use any sql tool, eg isql:`$ isql   MSSQLTestServer quickbooks pcgi21`



if you need select all record in tables
```
SQL> select a.id, a.ocrfiles_id, a.ffilename, a.fpage, b.fpages from ocrentries a, ocrfiles b where a.ocrfiles_id=b.id order by a.ocrfiles_id, a.fpage
```
if you need select record with id=61 in table ocrentries  
```
SQL> select a.id, a.ocrfiles_id, a.ffilename, a.fpage, b.fpages from ocrentries a, ocrfiles b where a.ocrfiles_id=b.id and b.id=61 order by a.ocrfiles_id, a.fpage
```



If you need export data from record with id=333 from table ocrentries you can use tool `export_data.pl`:
```
$ /home/directware/watchdogocr/export_data.pl --id=333
Save files for record with id=333
333.txt, 333.xml, 333.html, 333.json
$ ls -la /home/directware/watchdogocr/333.*
-rw-rw-r-- 1 directware directware  37453 Nov  3 07:42 /home/directware/watchdogocr/333.html
-rw-rw-r-- 1 directware directware 929748 Nov  3 07:42 /home/directware/watchdogocr/333.json
-rw-rw-r-- 1 directware directware   2920 Nov  3 07:42 /home/directware/watchdogocr/333.txt
-rw-rw-r-- 1 directware directware 246849 Nov  3 07:42 /home/directware/watchdogocr/333.xml
```



  Licensing
  ---------
	GNU

  Contacts
  --------

     o korolev-ia [at] yandex.ru
     o http://www.unixpin.com

