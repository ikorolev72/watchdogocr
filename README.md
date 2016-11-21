#						watchdogocr


##  What is it?
##  -----------
A "watchdog" script running in background on linux servers and 
scanning pdf files in folder. New files cut by pages and push into queue.
All pages ocr and every page save in to database (MSSQL) in xml, txt, json, html formats.

##  The Latest Version

	version 1.3 2016.11.20
	
##  Whats new
	+ Processed files move to finished directory
	+ Queue based on database records ( before - use filenames )
	+ 
	+ 

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
CREATE TABLE OCRFiles ( ID int IDENTITY(1,1) PRIMARY KEY, ffilename varchar( 255 ) not null , fpages int not null, EntryTime DATETIME NOT NULL DEFAULT GETDATE(), fstatus varchar(32) ; ) ;
CREATE TABLE OCREntries ( ID int IDENTITY(1,1) PRIMARY KEY, ffilename varchar( 255 ) not null , fpage int not null, EntryTime DATETIME NOT NULL DEFAULT GETDATE(), 
ftext varchar, fxml varchar, fhtml varchar, fjson varchar, ocrfiles_id int , pstatus varchar(32) ) ;
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
*       *       *       *       *       /home/directware/watchdogocr/watchdogocr.pl >>  /home/directware/watchdogocr/var/log/watchdogocr.pl.log 2>&1
   ```
   3. From command line as daemon. Run ```/usr/bin/nohup /home/directware/watchdogocr/watchdogocr.pl --daemon >/dev/null 2>&1 &```
   
Put your pdf files into directory `/home/directware/docs/in`. After this watchdogocr will start processing your files during 30 seconds.
Processing files moved into `/home/directware/docs/in/process`, faled files moved into `/home/directware/docs/in/failed`. 
All logs saved into `/home/directware/watchdogocr/var/log` .


### How to queue files

There is the column 'fstatus' In table OCRFiles with possible values: added, running, failed, finished.
There is the column 'pstatus' In table OCREntries with possible values: added, running, failed, finished.


When you put pdf-file into $SCAN_DIR, wathchdogocr process 
	1. wathchdogocr process found this file in $SCAN_DIR
	2. move this file into $DIR_FOR_FILES_IN_PROCESS and add new record into table OCRFiles ( record status = 'added' )
	3. separate this file to pages and save all pages into $DIR_FOR_PAGES_OCR and insert for every page new record into OCREntries ( record status = 'added' )
	4. watchdogocr check the pages in running status and if have free resources then run pages in status 'added' to processing ( record status = 'running' )
	5. watchdogocr check how many page for every files are in status 'finished' or 'failed' and if all pages processed, then change status of file in table table OCRFiles to 'finished'
	6. failed pages and files move into $DIR_FOR_FAILED_OCR
	7. successfully finished files ( may be with failed pages ) move into $DIR_FOR_FINISHED_OCR
	



   
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
if you need select only processed files 
```
SQL> select * from ocrfiles where fstatus='finished'
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


### Failed OCR
WatchdogOCR use several external application :  `pdfinfo` and `pdfseparate` for separate files to pages,
`pypdfocr` ( `Tesseract-OCR` ) for ocr files, `pdf2txt.py` for extract info from pdf files. And error in any of 
those programm may lead to 'failed' status. Also the 'failed' status of file may be result of database 
error ( eg cannot connect to database ) and incorrect permissions ( if file cannot move, or save to some directory).
In any case all errors with descriptions are logged into log files in `$LOGDIR`.
In simple case possible move file from `$DIR_FOR_FAILED_OCR` to `$SCAN_DIR` for one more ocr attempt.



  Licensing
  ---------
	GNU

  Contacts
  --------

     o korolev-ia [at] yandex.ru
     o http://www.unixpin.com

