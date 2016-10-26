#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.0 2016.10.26
##############################

use Data::Dumper;
use Getopt::Long;
use Mail::Sendmail;
use DBI;
use lib "/home/directware/perl5/lib/perl5/x86_64-linux-gnu-thread-multi/"; 
use DBD::ODBC;


use watchdog_config;

GetOptions (
        'daemon|d' => \$daemon,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);

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
	exit 1;
}


if( $daemon ) {
	$DEBUG=0;
	while( 1 ) {
		foreach $i ( 0..$#SCAN_DIRS ) {
			scan_dir( $SCAN_DIRS[$i], $LAST_SCANED_TIME_DB[$i] );
		}	
		sleep( $SCAN_INTERVAL );
	}
} else {
		foreach $i ( 0..$#SCAN_DIRS ) {
			scan_dir( $SCAN_DIRS[$i], $LAST_SCANED_TIME_DB[$i] );
		}	
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
				next unless( ocr_file( $dir, $filename ) ); # if any error , then process next file 
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
	if( system( "/usr/local/bin/pypdfocr $dir/$filename" )!=0 ) {
		w2log( "Error while ocr file $filename");
		return 0;
	}
	$filename=~/^(\w+)_ocr.pdf$/;
	my $perfix=$1; # for temporary files and search the ocr files
	my $filename_ocr="$dir/${perfix}_ocr.pdf";

	unless( -r $filename_ocr ) {
		w2log( "File $filename_ocr do not exist (or not readable)"); 
		return 0;
	}
	
	my $filename_tmp="$TMPDIR/$perfix.txt";	
	if( system( "/usr/local/bin/pdf2txt.py -o $filename_tmp -t text $filename_ocr" )!=0 ) {
		w2log( "Error while convert file $dir/$filename to text");
		return 0;		
	}
	my $filename_tmp="$TMPDIR/$perfix.xml";	
	if( system( "/usr/local/bin/pdf2txt.py -o $filename_tmp -t xml $filename_ocr" )!=0 ) {
		w2log( "Error while convert file $dir/$filename to xml");
		return 0;		
	}
	my $filename_tmp="$TMPDIR/$perfix.html";	
	if( system( "/usr/local/bin/pdf2txt.py -o $filename_tmp -t html $filename_ocr" )!=0 ) {
		w2log( "Error while convert file $dir/$filename to html");
		return 0;		
	}
	if( insert_record_into_database( "$dir/$filename", $perfix ) ) {
		w2log( "Error while convert file $dir/$filename to html");
		return 0;				
	}
	return 1;
}

# "/usr/local/bin/pdf2txt.py [-d] [-p pagenos] [-m maxpages] [-P password] [-o output] [-C] [-n] [-A] [-V] [-M char_margin] [-L line_margin] [-W word_margin] [-F boxes_flow] [-Y layout_mode] [-O output_dir] [-R rotation] [-S] [-t text|html|xml|tag] [-c codec] [-s scale] file .."
# "/usr/local/bin/pdf2txt.py -D auto -V -t text" 
# "/usr/local/bin/pdf2txt.py -t xml" 
# "/usr/local/bin/pdf2txt.py -t html" 

sub insert_record_into_database {
	my $ffilename=shift;
	my $perfix=shift;
#id        
#EntryTime 
#ftext     
#fjson     
#fxml      
#ffilename	
	my $fxml=ReadFile( "$TMPDIR/$perfix.xml" );
	my $ftext=ReadFile( "$TMPDIR/$perfix.txt" );
	my $fhtml=ReadFile( "$TMPDIR/$perfix.html" );

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
	open (IN,"$filename") || w2log("Can't open file $filename") ;
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
					
					
sub show_help {
print STDERR "
Check dirs, search keywords in logfiles and send mail if alert
Usage: $0  [ --daemon ]  [--help]
where:
Sample:
$0 --daemon
";
	exit (1);
}					