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
		WriteFile( "$id.xml", $row->{fxml} );
		WriteFile( "$id.html", $row->{fhtml} );
		WriteFile( "$id.json", $row->{fjson} );
	} else {
		print "Cannot get record with id=$id\n";
	}
	
					
					
sub show_help {
print STDERR "
Export data from table with selected id
Usage: $0  [ --id=id ]  [--help]
where:
Sample:
$0 --id=50
";
	exit (1);
}					