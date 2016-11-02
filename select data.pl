#!/usr/bin/perl

use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;


GetOptions (
        'id|f=i' => \$id,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);

unless( $id ) {
	show_help();
}


my $dbh=db_connect();

	my $sql="select * from OCREntries where id=$id ;";
	my $sth;
	my $rv;
	eval {
		$sth = $dbh->prepare( $sql );
		$rv = $sth->execute(  );
	};

	if( $@ ){
		w2log( "Error. Sql:$sql . Error: $@" );
		return 0;
	}
	if( my $row = $sth->fetchrow_hashref ) {
		print "Save files for record with id=$id\n";
		print "$id.txt, $id.xml, $id.html, $id.json\n";
		WriteFile( "$id.txt", $row->{ftext} );
		WriteFile( "$id.xml", $row->{xml} );
		WriteFile( "$id.html", $row->{html} );
		WriteFile( "$id.json", $row->{fjson} );
	} else {
		print "Cannot get record with id=$id\n";
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