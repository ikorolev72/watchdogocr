#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.1 2016.10.31
##############################


use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;

GetOptions (
        'filename|f=s' => \$filename,
        'master|m=s' => \$filename_master,
        'page|p=i' => \$page,
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
$filename_pdf=~/^$CHECK_FILE_MASK$/;
my $prefix=$1; # for temporary files and search the ocr files
my $filename_ocr="${prefix}_ocr.pdf";

my $filename_master=$filename_pdf;
my $page=1;
if( $filename_pdf=~/$CHECK_FILE_MASK_PAGE$/ ) {
	$filename_master="$1.pdf";		
	$page=$2;	
}


if( ocr_file( $dir, $filename_pdf, $filename_ocr, $prefix ) ) {
	w2log( "File $dir/$filename_ocr ocr succesfully");

	# 
	my $dbh=db_connect() || w2log( "Cannot connect to database");
	unless( insert_record_into_database( $dbh, $filename_master, $prefix, $page ) ) {
		w2log( "Cannot insert record into database");
	}
	db_disconnect($dbh);
	#

	unless( rename( "$DIR_FOR_FILES_IN_PROCESS/$filename_master", "$DIR_FOR_FINISHED_OCR/$filename_master" ) ) {
		w2log( "Cannot rename file '$filename_master' to '$DIR_FOR_FINISHED_OCR/$filename_master': $!");
	}
	unlink "$filename" ;
	unlink "$dir/$filename_ocr" ;
} else {
	w2log( "Error while ocr file $dir/$filename_ocr");
	unless( rename( "$DIR_FOR_FILES_IN_PROCESS/$filename_master", "$DIR_FOR_FAILED_OCR/$filename_master" ) ) {
		w2log( "Cannot rename file '$filename_master' to '$DIR_FOR_FAILED_OCR/$filename_master': $!");
	}
	unlink "$filename" ;
	unlink "$dir/$filename_ocr";
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
	#$filename=~/^$CHECK_FILE_MASK$/;
	#my $prefix=$1; # for temporary files and search the ocr files
	#my $filename_ocr="${prefix}_ocr.pdf";


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
		$rv = $sth->execute( $EntryTime, $ftext, $fjson, $fhtml, $fxml, $ffilenamem, $fpage  );
#		$sth->bind_param(1, $EntryTime);		
#		$sth->bind_param(2, $ftext, DBI::SQL_LONGVARCHAR);		
#		$sth->bind_param(3, $fjson, DBI::SQL_LONGVARCHAR);		
#		$sth->bind_param(4, $fhtml, DBI::SQL_LONGVARCHAR);		
#		$sth->bind_param(5, $fxml, DBI::SQL_LONGVARCHAR);		
#		$sth->bind_param(6, $ffilename);
#		$sth->execute()
	};

	if( $@ ){
		w2log( "Error. Sql:$sql . Error: $@" );
		return 0;
	}
	return 1;
}
	


					
sub show_help {
print STDERR "
ocr one file. Usualy used for ocr one page ( master file cuted by pages )
Usage: $0  --filename=filename --master=filename_of_master --page=page_number [--help]
where:
filename - pdf file with absolute path for ocr
master - master pdf file with absolute path
page - page number 
Sample:
$0 --filename=/dir/filename_PAGE6.pdf --master=/dir/filename.pdf --page=6
if file do not cutted by pages
$0 --filename=/dir/filename.pdf --master=/dir/filename.pdf --page=1
";
	exit (1);
}					