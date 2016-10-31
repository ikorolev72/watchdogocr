#!/usr/bin/perl
# korolev-ia [at] yandex.ru
# version 1.1 2016.10.31
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
		scan_dir(  );
		sleep( $SCAN_INTERVAL );
	}
} else {
		scan_dir(  );
}

exit(0);


sub scan_dir {	
	my @running_dir_files=get_files_in_dir( $DIR_FOR_RUNNING_OCR , "^$CHECK_FILE_MASK\$" );
	my @scan_dir_files=get_files_in_dir( $SCAN_DIR, "^$CHECK_FILE_MASK\$" );
	if( $#scan_dir_file < 0 ) {
		return 1;
	}
	foreach $i ( $#running_dir_files..$MAX_FILES_IN_OCR_QUEUE ) {
		my $filename=@running_dir_files[$i];
		if( rename( "$SCAN_DIR/$filename", "$DIR_FOR_RUNNING_OCR/$filename" ) ) {
			#system( "$WATCHDOGOCR_FILE --file='$DIR_FOR_RUNNING_OCR/$filename' > '$LOGDIR/$filename.ocr.log' 2>&1 &")
		} else {
			w2log( "Cannot rename file '$SCAN_DIR/$filename' to '$DIR_FOR_RUNNING_OCR/$filename': $!");
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