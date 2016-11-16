#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.3 2016.11.16
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
		check_finished_ocr();
		sleep( $SCAN_INTERVAL );
	}
} else {
		scan_dir();
		scan_page_dir();
		check_finished_ocr();
}

exit(0);


sub check_finished_ocr {
	# check if all pages of pdf docs finished ( or failed )
	my $dbh=db_connect() ;
	unless( $dbh ) {
		w2log( "Cannot connect to database") ;
		return 0;
	}
	my $sql="select id from ocrfiles where fstatus='added' ";
	eval {
		my $sth = $dbh->prepare( $sql );
		$sth->execute( );
	};
	if( $@ ){
		w2log( "Cannot select record. Sql:$sql . Error: $@" );
		db_disconnect($dbh);		
		return 0;
	}
	while( my $row=$sth->fetchrow_hashref ) {
		my $sql="select count(*) as cnt from ocrentries where pstatus in ( 'failed', 'finished' ) and ocrfiles_id=? ";
		eval {
			my $sth = $dbh->prepare( $sql );
			$sth->execute( $row->{id} );
		};
		if( $@ ){
			w2log( "Cannot select record. Sql:$sql . Error: $@" );
			db_disconnect($dbh);			
			return 0;
		}
		my $nrow=$sth->fetchrow_hashref ;
		if( $nrow->{cnt} == $row->{pages} ) {
				my $srow;
				$srow->{status}='finished';	
				UpdateRecord( $dbh, $row->{id}, 'OCRFiles', $srow ) ;
				w2log( "Processing of file $row->{ffilename} finished successfully");				
				unless( rename( "$DIR_FOR_FILES_IN_PROCESS/$row->{ffilename}", "$DIR_FOR_FINISHED_OCR/$row->{ffilename}" ) ) {
					w2log( "Cannot rename file '$DIR_FOR_FILES_IN_PROCESS/$row->{ffilename}' to '$DIR_FOR_FINISHED_OCR/$row->{ffilename}': $!");				
				}				
		}
	}
	db_disconnect($dbh);			
	return 1;	
}


sub scan_dir {	
	# this function scan dir,  loking for new pdf-file, cut this file to pages
	# insert into database info about this file
	my @scan_dir_files=get_files_in_dir( $SCAN_DIR, "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_files < 0 ) {
		return 1;
	}	
	my $dbh=db_connect() || w2log( "Cannot connect to database") ;
	foreach $filename ( @scan_dir_files ) {		

		# check if file uploaded to dir - we check the size of this file
		# if size changed, then try process next file
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat( "$SCAN_DIR/$filename" );
		my $size0=$size;
		sleep 10;
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat( "$SCAN_DIR/$filename" );
		if( $size != $size0 ) {
			next;
		}
		#
		my $row;
		$row->{ffilename}=$filename;
		$row->{fpages}=0 ;
		$row->{fstatus}='added';
		my $id=InsertRecord( $dbh, 'OCRFiles', $row );	
		
#		my $sql="insert into OCRFiles ( ffilename, fpages, fstatus ) OUTPUT Inserted.ID values( '$filename', 0, 'added' ) ;";
#		my $id=0;
#		eval {
#			my $sth = $dbh->prepare( $sql );
#			$sth->execute();
#			if( my $row = $sth->fetchrow_hashref ) {
#				$id=$row->{id};
#			}
#		};
#		if( $@ ){
#			w2log( "Error. Sql:$sql . Error: $@" );
#			db_disconnect($dbh);
#			return 0;
#		}		

		# cut pdf file by page
		my $dt=time();
		if( system( "/usr/bin/pdfseparate '$SCAN_DIR/$filename' '${DIR_FOR_PAGES_OCR}/${dt}_ID${id}_PAGE%d.pdf' >> $LOGDIR/pdfseparate.log" )==0 ) {
			if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_FILES_IN_PROCESS/$filename" ) ) {
				my @Pages=get_files_in_dir( $DIR_FOR_PAGES_OCR, "^${dt}_ID${id}_PAGE\\d+\.pdf\$" );
				my $row;
				$row->{fpages}=$#Pages+1;				
				$row->{status}='running';
				UpdateRecord( $dbh, $id, 'OCRFiles', $row ) ;
				
				my @scan_dir_for_pages_ocr=get_files_in_dir( $DIR_FOR_PAGES_OCR , "^${dt}_ID${id}_PAGE\d+\.pdf\$" );
				
				foreach my $pagename ( sort @scan_dir_for_pages_ocr ) {
					my ( undef , $page, undef )=get_prefix_page( $pagename );
					my $row;
					$row->{EntryTime}=get_date();
					$row->{ffilename}=$pagename;
					$row->{fpage}=$page ;
					$row->{ocrfiles_id}=$id;
					$row->{pstatus}='added';
					InsertRecord( $dbh, 'OCREntries' , $row );						
				}				
				
			} else {
				# if this file left in scaning folder, then it may go to ocr queue again
				w2log( "Cannot rename file '$SCAN_DIR/$filename' to 'DIR_FOR_FILES_IN_PROCESS/$filename': $!");				
				unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID*_PAGE*.pdf"; 
				rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
				DeleteRecord( $dbh, $id, 'OCRFiles' );
			}					
		} else {
				w2log( "Cannot cut the file '$SCAN_DIR/$filename' to pages");
				my $row;
				$row->{status}='failed';				
				UpdateRecord( $dbh, $id, 'OCRFiles', $row ) ;
				rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;				
				unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID*_PAGE*.pdf"; 

				# cutting by page. not actual. prepare to remove
				if( 0 ) {		
				w2log( "Cannot cut the entire file '$SCAN_DIR/$filename' to pages");
				w2log( "Try cut the file '$SCAN_DIR/$filename' for one page");
				unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID*_PAGE*.pdf"; 

				my $pages_in_pdf=`"/usr/bin/pdfinfo -meta '$SCAN_DIR/$filename'  | grep ^Pages: | sed 's/^Pages: *//'"`;
				$pages_in_pdf=~s/\D//g;
				unless( $pages_in_pdf ){
					w2log( "Cannot count the pages in pdf file '$SCAN_DIR/$filename'. Cannot processing this file.");				
					unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID*_PAGE*.pdf"; 
					rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
					DeleteRecord( $dbh, $id, 'OCRFiles' );	
					return 0;
				}

				my $processed_page=0;
				for $page ( 1..$pages_in_pdf) {
					# if problems with pdfseparate, then 
					# will try separate by one page and ignore errors
					if( system( "/usr/bin/pdfseparate '$SCAN_DIR/$filename' -f $page -l $page '${DIR_FOR_PAGES_OCR}/${dt}_ID${id}_PAGE%d.pdf' >> $LOGDIR/pdfseparate.log" )==0 ){
						$processed_page++;
					} else{
						w2log( "Cannot cut the page $page from file '$SCAN_DIR/$filename'");
					}
					# start working page process
					scan_page_dir();
				}
				unless( $processed_page ) {
				# brocken file, nothing to help
					w2log( "Cannot rename file '$SCAN_DIR/$filename' to 'DIR_FOR_FILES_IN_PROCESS/$filename': $!");				
					unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID*_PAGE*.pdf"; 
					rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
					DeleteRecord( $dbh, $id, 'OCRFiles' );					
				}
				}				
		} 
	}
	db_disconnect($dbh);
	return 1;
}




sub scan_page_dir {	
	# scan dir with 'one page' pdf files
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