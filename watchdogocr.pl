#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.1 2016.10.31
##############################

use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;


GetOptions (
        'daemon|d' => \$daemon,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);


if( $daemon ) {
	$DEBUG=0;
	while( 1 ) {
		scan_dir();
		scan_page_dir();
		sleep( $SCAN_INTERVAL );
	}
} else {
		scan_dir();
		scan_page_dir();
}

exit(0);


# this function scan dir,  loking for new pdf-file, cut this file to pages
# and then  
sub scan_dir {	
	my @scan_dir_files=get_files_in_dir( $SCAN_DIR, "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_files < 0 ) {
		return 1;
	}
	foreach $filename ( @scan_dir_files ) {		
		# here must be cutting utilite for pdf file. For debuging - simple move file
		# if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_PAGES_OCR/$filename" ) ) {
		
		$filename=~/^$CHECK_FILE_MASK$/;
		my $prefix=$1; # for temporary files and search the ocr files		
		
		# cut pdf file by page
		if( system( "/usr/bin/pdfseparate '$SCAN_DIR/$filename' '${DIR_FOR_PAGES_OCR}/${prefix}_PAGE%d.pdf' >> $LOGDIR/pdfseparate.log" )!=0 ) {
				w2log( "Cannot cut the file '$SCAN_DIR/$filename' to pages");
				unlink glob "${DIR_FOR_PAGES_OCR}/${prefix}_PAGE*.pdf"; 
		} else {
			if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_FILES_IN_PROCESS/$filename" ) ) {
				#my $pages=`/usr/bin/pdfinfo -meta '$SCAN_DIR/$filename' | grep ^Pages: | sed 's/^Pages: *//'` ; 
				my @Pages=get_files_in_dir( $DIR_FOR_PAGES_OCR, "^${prefix}_PAGE\\d+\.pdf\$" );
				my $pages=$#Pages+1;
				$pages=0 unless( $pages); # if any error when get counter of pages			
				my $dbh=db_connect() || w2log( "Cannot connect to database") ;
				my $sql="insert into OCRFiles ( ffilename, fpages ) values( '$SCAN_DIR/$filename', $pages ) ;";
				eval {
					my $sth = $dbh->prepare( $sql );
					$sth->execute();
				};
				if( $@ ){
					w2log( "Error. Sql:$sql . Error: $@" );
					return 0;
				}		
				db_disconnect($dbh);
				#scan_page_dir( $filename ) ;
			}			
		} 
	}
	return 1;
}


sub scan_page_dir {	
	#my $filename_master=shift;
	my @scan_dir_running_ocr=get_files_in_dir( $DIR_FOR_RUNNING_OCR , "^$CHECK_FILE_MASK\$" );
	my @scan_dir_for_pages_ocr=get_files_in_dir( $DIR_FOR_PAGES_OCR , "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_for_pages_ocr < 0 ) {
		return 1;
	}

	my $counter=$#scan_dir_running_ocr;
	print "## $#scan_dir_running_ocr ## $#scan_dir_for_pages_ocr \n";
	foreach $filename( @scan_dir_for_pages_ocr ) {
#		if ( $filename=~/([\w|\s]+)_PAGE(\d+)\.pdf$/ ) {
		if ( $filename=~/$CHECK_FILE_MASK_PAGE$/ ) {
			my $filename_master="$1.pdf";		
			my $page=$2;
			$page=1 unless( $page );
			if( $counter++ > $MAX_FILES_IN_OCR_QUEUE ) {
				last;
			}
			if( rename( "$DIR_FOR_PAGES_OCR/$filename", "$DIR_FOR_RUNNING_OCR/$filename" ) ) {
				#system( "$WATCHDOGOCR_FILE --filename='$DIR_FOR_RUNNING_OCR/$filename' --master='$filename_master' --page=$page > '$LOGDIR/$filename.ocr.log' 2>&1 &");
				print "$WATCHDOGOCR_FILE --filename='$DIR_FOR_RUNNING_OCR/$filename' --master='$filename_master' --page=$page > '$LOGDIR/$filename.ocr.log' 2>&1 &\n";
			} else {
				w2log( "Cannot rename file '$DIR_FOR_PAGES_OCR/$filename' to '$DIR_FOR_RUNNING_OCR/$filename': $!");
				return 0;
			}
		}
	}
	return 1;
}


					
sub show_help {
print STDERR "
Check dirs, search new files, ocr and save result into database
Usage: $0  [ --daemon ]  [--help]
where:
Sample:
$0 --daemon
";
	exit (1);
}					