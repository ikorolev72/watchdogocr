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


sub scan_dir {	
	# this function scan dir,  loking for new pdf-file, cut this file to pages
	# insert into database info about this file
	my @scan_dir_files=get_files_in_dir( $SCAN_DIR, "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_files < 0 ) {
		return 1;
	}
	my $dbh=db_connect() || w2log( "Cannot connect to database") ;
	foreach $filename ( @scan_dir_files ) {		
		my $sql="insert into OCRFiles ( ffilename, fpages ) OUTPUT Inserted.ID values( '$filename', 0 ) ;";
		my $id=0;
		eval {
			my $sth = $dbh->prepare( $sql );
			$sth->execute();
			if( my $row = $sth->fetchrow_hashref ) {
				$id=$row->{id};
			}
		};
		if( $@ ){
			w2log( "Error. Sql:$sql . Error: $@" );
			db_disconnect($dbh);
			return 0;
		}		

		# cut pdf file by page
		my $dt=time();
		if( system( "/usr/bin/pdfseparate '$SCAN_DIR/$filename' '${DIR_FOR_PAGES_OCR}/${dt}_ID${id}_PAGE%d.pdf' >> $LOGDIR/pdfseparate.log" )!=0 ) {
				w2log( "Cannot cut the file '$SCAN_DIR/$filename' to pages");
				unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_PAGE*.pdf"; 
				rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
				DeleteRecord( $dbh, $id, 'OCRFiles' );
		} else {
			if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_FILES_IN_PROCESS/$filename" ) ) {
				my @Pages=get_files_in_dir( $DIR_FOR_PAGES_OCR, "^${dt}_ID${id}_PAGE\\d+\.pdf\$" );
				my $row;
				$row->{fpages}=$#Pages+1;				
				UpdateRecord( $dbh, $id, 'OCRFiles', $row ) ;
			} else {
				# if this file left in scaning folder, then it may go to ocr queue again
				w2log( "Cannot rename file '$SCAN_DIR/$filename' to 'DIR_FOR_FILES_IN_PROCESS/$filename': $!");				
				unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_PAGE*.pdf"; 
				rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
				DeleteRecord( $dbh, $id, 'OCRFiles' );
			}					
		} 
	}
	db_disconnect($dbh);
	return 1;
}


sub scan_page_dir {	
	# scen dir with 'one page' pdf files
	# and run jobs
	my @scan_dir_running_ocr=get_files_in_dir( $DIR_FOR_RUNNING_OCR , "^$CHECK_FILE_MASK\$" );
	my @scan_dir_for_pages_ocr=get_files_in_dir( $DIR_FOR_PAGES_OCR , "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_for_pages_ocr < 0 ) {
		return 1;
	}

	my $counter=$#scan_dir_running_ocr;
	foreach $filename( sort @scan_dir_for_pages_ocr ) {
		my ( $prefix_master, $page, $id )=get_prefix_page( $filename);
		if ( $id ) {
			if( $counter++ > $MAX_FILES_IN_OCR_QUEUE ) {
				last;
			}
			if( rename( "$DIR_FOR_PAGES_OCR/$filename", "$DIR_FOR_RUNNING_OCR/$filename" ) ) {
				my $cmd="$WATCHDOGOCR_FILE --filename='$DIR_FOR_RUNNING_OCR/$filename'  --remove >> '$LOGDIR/${prefix_master}_${id}.log' 2>&1 &";
				if( $DEBUG>0 ) {
					print "$cmd\n";
				} 
				if( $DEBUG<2 ) {
					system( $cmd );
				} 
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