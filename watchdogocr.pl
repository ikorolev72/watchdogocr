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


if( -f $PIDFILE && -r $PIDFILE ) {
	my $pid=ReadFile( $PIDFILE );
	if( $pid=~/^\d+$/ ) {
		if( kill( 0, $pid ) ) {
			run_page_ocr();
			#w2log( "Another process $0 is running. Exiting.");
			exit 0;
		}
	}
}
WriteFile( $PIDFILE , $$ );

if( $daemon ) {
	$DEBUG=0;
	while( 1 ) {
		scan_dir();
		run_page_ocr();
		#scan_page_dir();
		check_finished_ocr();
		sleep( $SCAN_INTERVAL );
	}
} else {
		scan_dir();
		run_page_ocr();
		#scan_page_dir();
		check_finished_ocr();
}
unlink( $PIDFILE );
exit(0);


sub check_finished_ocr {
	# check if all pages of pdf docs finished ( or failed )
	my $dbh=db_connect() ;
	unless( $dbh ) {
		w2log( "Cannot connect to database") ;
		return 0;
	}
	my $sql="select * from ocrfiles where fstatus in ( 'added', 'running' ) ";
	my $sth;
	eval {
		$sth = $dbh->prepare( $sql );
		$sth->execute( );
	};
	if( $@ ){
		w2log( "Cannot select record. Sql:$sql . Error: $@" );
		db_disconnect($dbh);		
		return 0;
	}
	my %Records;
	while( my $row=$sth->fetchrow_hashref ) {
		my $id=$row->{id};
		$Records{ $id } = $row ;
	}
	my %UpdatedId;
	foreach $id ( keys %Records ) {
		my $fpages=$Records{ $id }->{fpages};
		#my $row=$Records{ $id };
		#my $sql="select count(*) as cnt, b.id from ocrentries a, ocrfiles b where a.pstatus in ( 'failed', 'finished' ) and a.ocrfiles_id=b.id and b.fstatus='added' ";
		my $sql="select count(*) as cnt from ocrentries where pstatus in ( 'failed', 'finished' ) and ocrfiles_id=$id; ";
		my $sth;
		eval {
			$sth = $dbh->prepare( $sql );
			$sth->execute();
		};
		if( $@ ){
			w2log( "Cannot select record. Sql:$sql . Error: $@" );
			db_disconnect($dbh);
			return 0;
		}
		while( my $row=$sth->fetchrow_hashref ) {
			if( $row->{cnt} == $fpages ) {
				$UpdatedId{ $id } = $row ;
			}
		}		
	}		
	foreach $id ( keys %UpdatedId ) {
		my $row=$Records{ $id };		
		my $srow;
		$srow->{fstatus}='finished';	
		UpdateRecord( $dbh, $id , 'OCRFiles', $srow ) ;
		w2log( "Processing of file $row->{ffilename} finished successfully");				
		unless( rename( "$DIR_FOR_FILES_IN_PROCESS/$row->{ffilename}", "$DIR_FOR_FINISHED_OCR/$row->{ffilename}" ) ) {
			w2log( "Cannot rename file '$DIR_FOR_FILES_IN_PROCESS/$row->{ffilename}' to '$DIR_FOR_FINISHED_OCR/$row->{ffilename}': $!");				
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
		
		# cut pdf file by page
		my $dt=time();
		sleep 1;
		if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_FILES_IN_PROCESS/$filename" ) ) {
			unless( system( "/usr/bin/pdfseparate '$DIR_FOR_FILES_IN_PROCESS/$filename' '${DIR_FOR_PAGES_OCR}/${dt}_ID${id}_PAGE%d.pdf' >> $LOGDIR/pdfseparate.log" )==0 ) {
				w2log( "Cannot cut the file '$DIR_FOR_FILES_IN_PROCESS/$filename' to pages");
				my $row;
				$row->{fstatus}='failed';				
				UpdateRecord( $dbh, $id, 'OCRFiles', $row ) ;
				rename( "$DIR_FOR_FILES_IN_PROCESS/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;				
				unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID${id}_PAGE*.pdf"; 
				next;
			} 
				my @Pages=get_files_in_dir( $DIR_FOR_PAGES_OCR, "^${dt}_ID${id}_PAGE\\d+\\.pdf\$" );
				my $row;
				$row->{fpages}=$#Pages+1;				
				$row->{fstatus}='running';
				UpdateRecord( $dbh, $id, 'OCRFiles', $row ) ;
				
				my $file_mask="^${dt}_ID${id}_PAGE\\d+\.pdf\$" ;
				my @scan_dir_for_pages_ocr=get_files_in_dir( $DIR_FOR_PAGES_OCR , $file_mask );
				
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
			unlink glob "${DIR_FOR_PAGES_OCR}/${dt}_ID${id}_PAGE*.pdf"; 
			rename( "$SCAN_DIR/$filename", "$DIR_FOR_FAILED_OCR/$filename" ) ;
			DeleteRecord( $dbh, $id, 'OCRFiles' );
		}					
		# only one file processing
		#last;
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
				#
				# if many files processing start, we need a little pause before every
				sleep 4;
				#
			} else {
				w2log( "Cannot rename file '$DIR_FOR_PAGES_OCR/$filename' to '$DIR_FOR_RUNNING_OCR/$filename': $!");
				return 0;
			}
		}
	}
	return 1;
}



sub run_page_ocr {
	my $dbh=db_connect() ;

	my $sql="select top $MAX_FILES_IN_OCR_QUEUE id,ffilename from OCREntries where pstatus='added' order by id" ;
	my $page_id=0;
	my $sth;
	eval {
		$sth = $dbh->prepare( $sql );
		$sth->execute( );
		if( my $row = $sth->fetchrow_hashref ) {
			$page_id=$row->{id};
		}			
	};	
	if( $@ ){
		w2log( "Cannot select record. Sql:$sql . Error: $@" );
		db_disconnect($dbh);		
		return 0;
	}	
	my %UpdatedId;
	while( my $row=$sth->fetchrow_hashref ) {
		my $id=$row->{id};
		$UpdatedId{ $id } = $row ;
	}	
	my @scan_dir_running_ocr=get_files_in_dir( $DIR_FOR_RUNNING_OCR , "^$CHECK_FILE_MASK\$" );	
	my $counter=$#scan_dir_running_ocr;
	foreach my $id ( keys %UpdatedId ) {	
			if( $counter++ > $MAX_FILES_IN_OCR_QUEUE ) {
				last;
			}
			my $filename=$UpdatedId{$id}->{ffilename};
			my ( $prefix_master, $page, undef )=get_prefix_page( $filename);

			if( rename( "$DIR_FOR_PAGES_OCR/$filename", "$DIR_FOR_RUNNING_OCR/$filename" ) ) {
				my $srow;		
				$srow->{pstatus}='running';	
				UpdateRecord( $dbh, $id , 'OCREntries', $srow ) ;
				w2log( "Start processing of file $filename");			
				my $cmd="/usr/bin/timeout 3600 $WATCHDOGOCR_FILE --filename='$DIR_FOR_RUNNING_OCR/$filename'  --remove >> '$LOGDIR/${prefix_master}_${id}.log' 2>&1 &";
				if( $DEBUG>0 ) {
					print "$cmd\n";
				} 
				if( $DEBUG<2 ) {
					system( $cmd );
				}
				#
				# if many files processing start, we need a little pause before every
				sleep 4;
				#
			} else {
				w2log( "Cannot rename file '$DIR_FOR_PAGES_OCR/$filename' to '$DIR_FOR_RUNNING_OCR/$filename': $!");
				my $srow;		
				$srow->{pstatus}='failed';	
				UpdateRecord( $dbh, $id , 'OCREntries', $srow ) ;
				w2log( "Processing of file $filename failed");							
			}
	}
	db_disconnect($dbh);	
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