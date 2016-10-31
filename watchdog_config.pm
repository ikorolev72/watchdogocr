# Config file for check_logs utilite
#
#
use File::Basename;
use Cwd;

# if $DEBUG=1 then print all messages to stderr.
# if $DEBUG=0 then write messages only to $LOGFILE
$DEBUG=1;

# main working dir
chdir ( dirname($0) );
$WORKING_DIR = getcwd();
#$WORKING_DIR='/home/directware/watchdogocr'; # uncomment this only if you use different file for binary and all other files


# check new files every $SCAN_INTERVAL ( in seconds ) for daemon mode
$SCAN_INTERVAL=60; 


# Dir for 'redirecti scanned error lines'
$LOGDIR="$WORKING_DIR/var/log";
$TMPDIR="$WORKING_DIR/var/tmp";


# log file for errors with check_logs script ( eg 'cannot open file', etc)
$LOGFILE="$LOGDIR/".basename($0).".log";

$SCAN_DIR='/home/directware/docs';
$DIR_FOR_PAGES_OCR="$SCAN_DIR/pages";
$DIR_FOR_RUNNING_OCR="$SCAN_DIR/running";
$DIR_FOR_FINISHED_OCR="$SCAN_DIR/finished";
$DIR_FOR_FAILED_OCR="$SCAN_DIR/failed";

$LAST_SCANED_TIME_DB="$WORKING_DIR/var/last_scaned_time_dir0.txt" ;
$CHECK_FILE_MASK='([\w|\s]+)(?<!_ocr)\.pdf';



# db settings
@DB_CONNECTION=(
	"dbi:ODBC:MSSQLTestServer", 
	"quickbooks", 
	"pcgi21"
	);
	
	

1;