#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.1 2016.10.31
##############################


use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;

GetOptions (
        'filename|f' => \$filename,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);

unless( $filename ) {
	show_help();
}

unless( -f $filename && -r $filename ) {
	w2log( "File $filename must be regular file and redable ") ;
	show_help();
}

my $filename_pdf=basename( $filename );
my $dir=dirname($filename);

if( ocr_file( $dir, $filename_pdf ) ) {
	w2log( "File $dir/$filename ocr succesfully");
	unless( rename( "$dir/$filename_pdf", "$DIR_FOR_FINISHED_OCR/$filename_pdf" ) ){
		w2log( "Cannot move file '$dir/$filename_pdf' to '$DIR_FOR_FINISHED_OCR/$filename_pdf'");	
	}
} else {
	w2log( "Error while ocr file $dir/$filename");
	unless( rename( "$dir/$filename_pdf", "$DIR_FOR_FAILED_OCR/$filename_pdf" )  ){
		w2log( "Cannot move file '$dir/$filename_pdf' to '$DIR_FOR_FAILED_OCR/$filename_pdf'");	
	}
	exit(1);
	# do someting , eg email to admin
}

exit(0);


sub ocr_file {
	my $dir=shift;	
	my $filename=shift;	
	if( system( "/usr/local/bin/pypdfocr '$dir/$filename' >>$LOGDIR/pypdfocr.log 2>&1" )!=0 ) {
		w2log( "Error while ocr file '$filename'");
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
	


					
sub show_help {
print STDERR "
ocr one file
Usage: $0  --filename=filename [--help]
where:
filename - pdf file with absolute path
Sample:
$0 --filename=/dir/filename.pdf
";
	exit (1);
}					