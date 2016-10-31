#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.0 2016.10.26
##############################

use Data::Dumper;
use Getopt::Long;
use DBI;
use lib "/home/directware/watchdogocr/"; 
use lib "/home/directware/perl5/lib/perl5/x86_64-linux-gnu-thread-multi/"; 
use DBD::ODBC;
#use Encode::Encoder qw(encoder);
use XML::Simple;
use JSON::XS;

use watchdog_config;

GetOptions (
        'daemon|d' => \$daemon,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);


if( $daemon ) {
	$DEBUG=0;
	while( 1 ) {
		scan_dir( $SCAN_DIR, $LAST_SCANED_TIME_DB );
		sleep( $SCAN_INTERVAL );
	}
} else {
		scan_dir( $SCAN_DIR, $LAST_SCANED_TIME_DB );
}

exit(0);


sub scan_dir {
	my $dir=shift; # scan this dir 
	my $lastchecked_file=shift; # read last checked time and save here the current time
	
	my $lastchecked_tmp=ReadFile( $lastchecked_file );
	my $lastchecked_db;
	if( $lastchecked_tmp ) {		
		eval "$lastchecked_tmp";
		if( $@ ){
			w2log( "Error: $@" );
		} else {
			$lastchecked_db=$VAR1;
		}
	}
	
	
	#my $time_now=get_date( time(), "%s%.2i%.2i_%.2i%.2i%.2i" );
	# we will save the current time and will check in future only new files

	unless( opendir(DIR, $dir) ) {
		w2log( "can't opendir $dir: $!" );	
		return 0;
	} 
	while( readdir(DIR) ) {
		my $filename=$_;
			my $filemask=$CHECK_FILE_MASK;
			if( $filename=~/^$filemask$/  && -f "$dir/$filename" ) {
				my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat( "$dir/$filename" );
				my $lines=0;
				
				if( $lastchecked_db->{$filename}->{mtime} ) {
					# if we check this file but it modified
					if( $mtime <= $lastchecked_db->{$filename}->{mtime} ) {
						next;
					}
				} 
				# next unless( ocr_file( $dir, $filename ) ); # if any error , then process next file 
				unless( ocr_file( $dir, $filename ) ) {
					w2log( "2.Error while ocr file $dir/$filename"); 					
					# do someting , eg email to admin
				} 
				$lastchecked_db->{$filename}->{mtime}=$mtime;
				
			}
			else {
				next;
			}
	}
	closedir DIR;
	
	# save the db into file
	# this file can be very big and we will save it to tmp file and then remove
	if( WriteFile( "$lastchecked_file.tmp", Dumper( $lastchecked_db )  ) ) {
		return 1 if( rename( "$lastchecked_file.tmp", $lastchecked_file ) );
	}
	w2log( "Cannot save the db file $lastchecked_file: $!" );
	return 0;
}

sub ocr_file {
	my $dir=shift;	
	my $filename=shift;	
	if( system( "/usr/local/bin/pypdfocr '$dir/$filename' >>$LOGDIR/pypdfocr.log 2>&1" )!=0 ) {
		w2log( "1.Error while ocr file '$filename'");
		return 0;
	}
	$filename=~/^([\w|\s]+)_ocr.pdf$/;
	my $prefix=$1; # for temporary files and search the ocr files
	my $filename_ocr="$dir/${prefix}_ocr.pdf";

	unless( -r $filename_ocr ) {
		w2log( "File $filename_ocr do not exist (or not readable)"); 
		return 0;
	}
# "/usr/local/bin/pdf2txt.py -D auto -V -t text" 
	
	my $filename_tmp="$TMPDIR/$prefix.txt";	
	if( system( "/usr/local/bin/pdf2txt.py -o '$filename_tmp' -t text '$filename_ocr' >>$LOGDIR/pdf2txt.py.log 2>&1" )!=0 ) {
		w2log( "Error while convert file '$dir/$filename' to text");
		return 0;		
	}
	my $filename_tmp="$TMPDIR/$prefix.xml";	
	if( system( "/usr/local/bin/pdf2txt.py -o '$filename_tmp' -t xml '$filename_ocr' >>$LOGDIR/pdf2txt.py.log 2>&1" )!=0 ) {
		w2log( "Error while convert file '$dir/$filename' to xml");
		return 0;		
	}
	my $filename_tmp="$TMPDIR/$prefix.html";	
	if( system( "/usr/local/bin/pdf2txt.py -o '$filename_tmp' -t html '$filename_ocr' >>$LOGDIR/pdf2txt.py.log 2>&1" )!=0 ) {
		w2log( "Error while convert file '$dir/$filename' to html");
		return 0;		
	}

	my $dbh=db_connect();
	unless( $dbh ) {
		w2log( "Cannot connect to database");
		db_disconnect($dbh);
		return 0;				
	}
	unless( insert_record_into_database( $dbh, "$dir/$filename", $prefix ) ) {
		w2log( "Cannot insert record into database");
		db_disconnect($dbh);
		return 0;				
	}
	db_disconnect($dbh);
	return 1;
}

sub db_connect {
	my $dbh = DBI->connect( @DB_CONNECTION,  {
		PrintError       => 0,
		RaiseError       => 1,
		AutoCommit       => 1,
		FetchHashKeyName => 'NAME_lc',
		# we will set buffer for strings to 50mb
		LongReadLen => 50000000, 
	}) ; 

	unless( $dbh ) {
		w2log( "Cannot connect to database: $!") ;
		return 0;
	}
	return $dbh;
}

sub db_disconnect {
	my $dbh=shift;
	$dbh->disconnect;
}


sub insert_record_into_database {
	my $dbh=shift;
	my $ffilename=shift;
	my $prefix=shift;
	
	#id        
	#EntryTime 
	#ftext     
	#fjson     
	#fxml      
	#ffilename	
	

	###########
	my $EntryTime=get_date( ); # by default
	my $ftext=ReadFile( "$TMPDIR/$prefix.txt" );	
	my $fxml=ReadFile( "$TMPDIR/$prefix.xml" );
	my $fhtml=ReadFile( "$TMPDIR/$prefix.html" );
	my $fjson=xml2json( $fxml ) ;
	
#		$ftext=encoder($ftext)->utf8->latin1;
#		$fxml=encoder($fxml)->utf8->latin1;
#		$fhtml=encoder($fhtml)->utf8->latin1;
		
		#print "fhtml:". substr( $fhtml, 0, 255)."\n" ;
		#print "fxml:". substr( $fxml, 0, 255)."\n" ;
		#print "ftxt:". substr( $ftext, 0, 255)."\n" ;
		#$ftext=substr( $ftext, 0, 14330);
		#$ftext=$dbh->quote( $ftext );
		

	my $sql="insert into OCREntries ( EntryTime,ftext,fjson,fhtml,fxml,ffilename ) values(  ?, ?, ?, ?, ?, ? ) ;";
	my $sth;
	my $rv;	
	eval {
		$sth = $dbh->prepare( $sql );
		#$rv = $sth->execute( $EntryTime, $ftext, $fjson, $fhtml, $fxml, $ffilename  );
		$sth->bind_param(1, $EntryTime);		
		$sth->bind_param(2, $ftext, DBI::SQL_LONGVARCHAR);		
		$sth->bind_param(3, $fjson, DBI::SQL_LONGVARCHAR);		
		$sth->bind_param(4, $fhtml, DBI::SQL_LONGVARCHAR);		
		$sth->bind_param(5, $fxml, DBI::SQL_LONGVARCHAR);		
		$sth->bind_param(6, $ffilename);
		$sth->execute()
	};

	if( $@ ){
		w2log( "Error. Sql:$sql . Error: $@" );
		return 0;
	}
	return 1;
}
	

sub get_date {
	my $time=shift() || time();
	my $format=shift || "%s-%.2i-%.2i %.2i:%.2i:%.2i";
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($time);
	$year+=1900;$mon++;
    return sprintf( $format,$year,$mon,$mday,$hour,$min,$sec);
}	


sub w2log {
	my $msg=shift;
	# daily log file
	my $log=shift;
	unless( $log ) {
		$log=$LOGFILE; 
	}
	open (LOG,">>$log") || print STDERR ("Can't open file $log. $msg") ;
	print LOG get_date()."\t$msg\n";
	print STDERR "$msg\n" if( $DEBUG );
	close (LOG);
}


sub ReadFile {
	my $filename=shift;
	my $ret="";
#	open (IN,"<:encoding(UTF-8)","$filename") || w2log("Can't open file $filename") ;
	open (IN,"$filename") || w2log("Can't open file $filename") ;
		binmode(IN);
		while (<IN>) { $ret.=$_; }
	close (IN);
	return $ret;
}	
					
sub WriteFile {
	my $filename=shift;
	my $body=shift;
	unless( open (OUT,">$filename")) { w2log("Can't open file $filename for write" ) ;return 0; }
	print OUT $body;
	close (OUT);
	return 1;
}	

sub AppendFile {
	my $filename=shift;
	my $body=shift;
	unless( open (OUT,">>$filename")) { w2log("Can't open file $filename for append" ) ;return 0; }
	print OUT $body;
	close (OUT);
	return 1;
}
					
sub xml2json {
        my $xml=shift;
		my $ref;
        eval { $ref=XMLin( $xml,  ForceArray=>0 , ForceContent =>0 , KeyAttr => 1, KeepRoot => 1, SuppressEmpty => '' ) } ;
                if($@) {
                        w2log ( "XML file $filename error: $@" );
                        return( undef );
						
                }
		my $coder = JSON::XS->new->utf8->pretty->allow_nonref; # bugs with JSON module and threads. we need use JSON::XS
		my $json = $coder->encode ($ref);
        return $json;
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