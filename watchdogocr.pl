#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.2 2016.11.02
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
sub scan_dir {	
	my @scan_dir_files=get_files_in_dir( $SCAN_DIR, "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_files < 0 ) {
		return 1;
	}
	foreach $filename ( @scan_dir_files ) {		
		my $prefix=get_prefix( $filename ) ; 	
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat( "$SCAN_DIR/$filename" );

		# cut pdf file by page
		if( system( "/usr/bin/pdfseparate '$SCAN_DIR/$filename' '${DIR_FOR_PAGES_OCR}/${prefix}_PAGE%d.pdf' >> $LOGDIR/pdfseparate.log" )!=0 ) {
				w2log( "Cannot cut the file '$SCAN_DIR/$filename' to pages");
				unlink glob "${DIR_FOR_PAGES_OCR}/${prefix}_PAGE*.pdf"; 
				rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
		} else {
			if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_FILES_IN_PROCESS/$filename" ) ) {
				my @Pages=get_files_in_dir( $DIR_FOR_PAGES_OCR, "^${prefix}_PAGE\\d+\.pdf\$" );
				my $pages=$#Pages+1;
				$pages=0 unless( $pages); # if any error when get counter of pages			
				my $dbh=db_connect() || w2log( "Cannot connect to database") ;
				my $sql="insert into OCRFiles ( ffilename, fpages ) values( '$filename', $pages ) ; SELECT id FROM ocrfiles WHERE id = SCOPE_IDENTITY();";
				eval {
					my $sth = $dbh->prepare( $sql );
					$sth->execute();
				};
				if( $@ ){
					w2log( "Error. Sql:$sql . Error: $@" );
					return 0;
				}		
				eval {
					if( my $row = $sth->fetchrow_hashref ) {		
					print "Save files for record with id=$row->{id}\n";	
				}
				db_disconnect($dbh);
			}			
		} 
	}
	return 1;
}


sub scan_page_dir {	
	my @scan_dir_running_ocr=get_files_in_dir( $DIR_FOR_RUNNING_OCR , "^$CHECK_FILE_MASK\$" );
	my @scan_dir_for_pages_ocr=get_files_in_dir( $DIR_FOR_PAGES_OCR , "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_for_pages_ocr < 0 ) {
		return 1;
	}

	my $counter=$#scan_dir_running_ocr;
	#print "## $#scan_dir_running_ocr ## $#scan_dir_for_pages_ocr \n";
	foreach $filename( @scan_dir_for_pages_ocr ) {
		if ( $filename=~/([\w|\s]+)_PAGE(\d+)\.pdf$/ ) {
			if( $counter++ > $MAX_FILES_IN_OCR_QUEUE ) {
				last;
			}
			if( rename( "$DIR_FOR_PAGES_OCR/$filename", "$DIR_FOR_RUNNING_OCR/$filename" ) ) {
				system( "$WATCHDOGOCR_FILE --filename='$DIR_FOR_RUNNING_OCR/$filename'  --remove > '$LOGDIR/$filename.ocr.log' 2>&1 &");
				#print "$WATCHDOGOCR_FILE --filename='$DIR_FOR_RUNNING_OCR/$filename' --remove > '$LOGDIR/$filename.ocr.log' 2>&1 &\n";
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