#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.2 2016.11.02
##############################


use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;

GetOptions (
        'filename|f=s' => \$filename,
        'remove|r' => \$remove_original,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);

unless( $filename || $filename_master || $page ) {
	show_help();
}

unless( -f $filename && -r $filename ) {
	w2log( "File $filename must be regular file and redable ") ;
	show_help();
}

my $filename_pdf=basename( $filename );
my $dir=dirname( $filename );

my $prefix=get_prefix( $filename_pdf );
my $filename_ocr="${prefix}_ocr.pdf";

my ( $prefix_master , $page )=get_prefix_page( $filename_pdf );

my $filename_master=$filename_pdf;
$filename_master="${prefix_master}.pdf" if( $page ) ;		


#print "$filename_pdf # $filename_ocr # $page # $filename_master\n";

if( ocr_file( $dir, $filename_pdf, $filename_ocr, $prefix ) ) {
	w2log( "File $dir/$filename_ocr ocr succesfully");

	# 
	my $dbh=db_connect() || w2log( "Cannot connect to database");
	unless( insert_record_into_database( $dbh, $filename_master, $prefix, $page ) ) {
		w2log( "Cannot insert record into database");
	}
	db_disconnect($dbh);

	unlink "$dir/$filename_ocr" ;
	if( $remove_original ) {
		unlink "$filename";
		unlink ( "$TMPDIR/$prefix.txt" ,  "$TMPDIR/$prefix.xml" ,"$TMPDIR/$prefix.html" ) ;
	}
} else {
	w2log( "Error while ocr file $dir/$filename_ocr");
	unless( rename( $filename, "$DIR_FOR_FAILED_OCR/$filename_pdf" ) ) {
		w2log( "Cannot rename file '$filename' to '$DIR_FOR_FAILED_OCR/$filename_pdf': $!");
	}

	unlink "$dir/$filename_ocr";
	#unlink ( "$TMPDIR/$prefix.txt" ,  "$TMPDIR/$prefix.xml" ,"$TMPDIR/$prefix.html" ) ;	
	# do someting , eg email to admin
	exit(1);
}

exit(0);





sub ocr_file {
	my $dir=shift;	
	my $filename=shift;	
	my $filename_ocr=shift;	
	my $prefix=shift;	
	if( system( "/usr/local/bin/pypdfocr '$dir/$filename' >>$LOGDIR/pypdfocr.log 2>&1" )!=0 ) {
		w2log( "Error while ocr file '$filename'");
		return 0;
	}

	unless( -r "$dir/$filename_ocr" ) {
		w2log( "File '$dir/$filename_ocr' do not exist (or not readable)"); 
		return 0;
	}
	
	my $filename_tmp="$TMPDIR/$prefix.txt";	
	if( system( "/usr/local/bin/pdf2txt.py -o '$filename_tmp' -t text '$dir/$filename_ocr' >>$LOGDIR/pdf2txt.py.log 2>&1" )!=0 ) {
		w2log( "Error while convert file '$dir/$filename' to text");
		return 0;		
	}
	my $filename_tmp="$TMPDIR/$prefix.xml";	
	if( system( "/usr/local/bin/pdf2txt.py -o '$filename_tmp' -t xml '$dir/$filename_ocr' >>$LOGDIR/pdf2txt.py.log 2>&1" )!=0 ) {
		w2log( "Error while convert file '$dir/$filename' to xml");
		return 0;		
	}
	my $filename_tmp="$TMPDIR/$prefix.html";	
	if( system( "/usr/local/bin/pdf2txt.py -o '$filename_tmp' -t html '$dir/$filename_ocr' >>$LOGDIR/pdf2txt.py.log 2>&1" )!=0 ) {
		w2log( "Error while convert file '$dir/$filename' to html");
		return 0;		
	}
	return 1;
}




sub insert_record_into_database {
	my $dbh=shift;
	my $ffilename=shift;
	my $prefix=shift;
	my $fpage=shift;
	

	###########
	my $EntryTime=get_date( ); # by default
	my $ftext=ReadFile( "$TMPDIR/$prefix.txt" );	
	my $fxml=ReadFile( "$TMPDIR/$prefix.xml" );
	my $fhtml=ReadFile( "$TMPDIR/$prefix.html" );
	my $fjson=xml2json( $fxml ) ;

	my $sql="insert into OCREntries ( EntryTime,ftext,fjson,fhtml,fxml,ffilename, fpage ) values(  ?, ?, ?, ?, ?, ?, ? ) ;";
	my $sth;
	my $rv;	
	eval {
		$sth = $dbh->prepare( $sql );
		$rv = $sth->execute( $EntryTime, $ftext, $fjson, $fhtml, $fxml, $ffilename, $fpage  );
	};

	if( $@ ){
		w2log( "Error. Sql:$sql . Error: $@" );
		return 0;
	}
	return 1;
}
	
	

sub show_help {
print STDERR "
ocr one file. 
Usage: $0  --filename=filename [ --remove ] [--help]
where:
filename - pdf file with absolute path for ocr
--remove - remove original pdf file if ocr is successfull
Sample:
$0 --filename=/dir/filename_PAGE6.pdf --remove
";
	exit (1);
}					