#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.3 2016.11.16
##############################


use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;

GetOptions (
        'filename|f=s' => \$filename,
        'remove|r' => \$remove,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);

unless( $filename  ) {
	show_help();
}

unless( -f $filename && -r $filename ) {
	w2log( "File $filename must be regular file and readable ") ;
	show_help();
}

my $filename_pdf=basename( $filename );
my $dir=dirname( $filename );

my $prefix=get_prefix( $filename_pdf );
my $filename_ocr="${prefix}_ocr.pdf";

my ( undef , $page, $id )=get_prefix_page( $filename_pdf );
	


#print "$filename_pdf # $filename_ocr # $page # $filename_master\n";

my $ocr_page_success=ocr_file( $dir, $filename_pdf, $filename_ocr, $prefix );
my $dbh=db_connect() || w2log( "Cannot connect to database");

	if( $ocr_page_success ) {
		w2log( "File $dir/$filename_ocr ocr succesfully");	
		my $row;
		$row->{ftext}=ReadFile( "$TMPDIR/$prefix.txt" );
		$row->{fxml}=ReadFile( "$TMPDIR/$prefix.xml" );
		$row->{fhtml}=ReadFile( "$TMPDIR/$prefix.html" );
		$row->{fjson}=xml2json( $row->{fxml} ) ;
		$row->{pstatus}='finished';
		
		my $sql="update OCREntries set ftext=? , fjson=?, fhtml=?, fxml=?, pstatus='finished' where ocrfiles_id=? and fpage=?" ;
		my $sth;
		eval {
			$sth = $dbh->prepare( $sql );
			$sth->execute( $ftext, $fjson, $fhtml, $fxml, $id, $page  );
		};			
		if( $@ ){
			w2log( "Cannot update record : id=$id, fpage=$page. Sql:$sql . Error: $@" );
		}		
		unlink "$dir/$filename_ocr" ;
		if( $remove ) {
			unlink "$filename";
			unlink ( "$TMPDIR/$prefix.txt" ,  "$TMPDIR/$prefix.xml" ,"$TMPDIR/$prefix.html" ) ;
		}
		
	} else {
		w2log( "Error while ocr file $dir/$filename_ocr");
		my $sql="update OCREntries set pstatus='failed' where ocrfiles_id=? and fpage=?" ;
		my $sth;
		eval {
			$sth = $dbh->prepare( $sql );
			$sth->execute( $id, $page  );
		};			
		if( $@ ){
			w2log( "Cannot update record : id=$id, fpage=$page. Sql:$sql . Error: $@" );
		}		
	
		unless( rename( $filename, "$DIR_FOR_FAILED_OCR/$filename_pdf" ) ) {
			w2log( "Cannot rename file '$filename' to '$DIR_FOR_FAILED_OCR/$filename_pdf': $!");
		}

		# remove all temporary files like ZZZ_ocr.pdf, ZZZ_text.pdf text_ZZZ.pdf
		unlink glob "${dir}/${prefix}_*text.pdf"; 
		unlink glob "${dir}/${prefix}_*ocr.pdf"; 
		unlink glob "${dir}/text_${prefix}_*.pdf"; 
		#unlink "$dir/$filename_ocr";
		unlink ( "$TMPDIR/$prefix.txt" ,  "$TMPDIR/$prefix.xml" ,"$TMPDIR/$prefix.html" ) ;	
		# do someting , eg email to admin
		exit(1);		
	}
	
db_disconnect($dbh);
exit 0;
	





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