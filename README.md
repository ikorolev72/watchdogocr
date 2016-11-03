#						watchdogocr


##  What is it?
##  -----------
A "watchdog" script running in background on linux servers and 
scanning pdf files in folder. New files cut by pages and push into queue.
All pages ocr and every page save in to database (MSSQL) in xml, txt, json,html formats.

### How to install


Edit the _watchdogocr_common.pm_ with your prefferences:
   +  $SCAN_DIR - dirs you plane to scan
   +  $CHECK_FILE_MASK - filemask for your pdf files


### How to run
There three ways to run:
   1. From command line. Usualy for testing resone. Simple run ```/home/directware/watchdogocr/watchdogocr.pl```
   2. From crontab. Add next line to your crontab with ```crontab -e``` command:
   ```
*	*	*	*	*	/home/directware/watchdogocr/watchdogocr.pl >/dev/null 2>&1
   ```
   3. From command line as daemon. Run ```/home/directware/watchdogocr/watchdogocr.pl --daemon &```
   
   
  Licensing
  ---------
	GNU

  Contacts
  --------

     o korolev-ia [at] yandex.ru
     o http://www.unixpin.com

