#!/usr/bin/perl

use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;


GetOptions (
        'sql=s' => \$sql,
        "help|h|?"  => \$help ) or show_help();

show_help() if($help);

unless( $sql ) {
	show_help();
}


my $dbh=db_connect();

	#my $sql="select * from OCREntries where id=$id ;";
	my $sth;
	my $rv;
	eval {
		$sth = $dbh->prepare( $sql );
		$rv = $sth->execute(  );
	};

	if( $@ ){
		w2log( "Error. Sql:$sql . Error: $@" );
		exit 1;
	}
	if( my $row = $sth->fetchrow_hashref ) {
		
		print "Save files for record with id=$row->{id}\n";	
	}
	print "Done\n";
	
					
					
sub show_help {
print STDERR "
Check dirs, search new files, ocr and save result into database
Usage: $0  [ --sql='sql string' ]  [--help]
where:
Sample:
$0 --sql='select id from  table'
";
	exit (1);
}					