#!/usr/bin/perl

use DBI;
use lib "/home/directware/perl5/lib/perl5/x86_64-linux-gnu-thread-multi/"; 
use DBD::ODBC;
use Getopt::Long;

my $dbh = DBI->connect("dbi:ODBC:MSSQLTestServer", "quickbooks", "pcgi21",  {
   PrintError       => 0,
   RaiseError       => 1,
   AutoCommit       => 1,
   FetchHashKeyName => 'NAME_lc',
   LongReadLen => 10000000,
}) || die $!; 


GetOptions (
        'id|i=i' => \$id,
        'filename|f=s' => \$filename );

if( !$id && ! -r $filename) {
	print "Usage: $0 --id=143 --filename=/dir/filename\n";
	exit;	
}
InsertRecord($dbh, $id, $filename);
#GetRecord($dbh);
exit 0;


sub ReadFile {
	my $filename=shift;
	my $ret="";
	open (IN,"$filename") || w2log("Can't open file $filename") ;
		while (<IN>) { $ret.=$_; }
	close (IN);
	return $ret;
}	

sub w2log {
	my $msg=shift;
	print $msg;
}


sub InsertRecord {
	my $dbh=shift;
	my $id=shift;
	my $filename=shift;
my $textbody=ReadFile( $filename );

my $quotedtext=$dbh->quote( $textbody );

	
my $sql="insert into OCREntry values( ?, ? ) ;";
my $sth ;
my $rv ;

eval {
	$sth = $dbh->prepare( $sql );
	$rv = $sth->execute( $id, $quotedtext );
};

	if( $@ ){
		print( "Error. Sql:$sql . Error: $@" );
		exit 1;
	}
print "all ok";
}

sub GetRecord {
	my $dbh=shift;
	my $id=shift;
	my $table=shift;
	#my $fields=shift || '*';
	my $stmt ="SELECT * from OCREntry ;";
	my $sth = $dbh->prepare( $stmt );
	my $rv;
	unless ( $rv = $sth->execute(  ) || $rv < 0 ) {
		w2log ( "Sql( $stmt ) Someting wrong with database  : $DBI::errstr" );
		return 0;
	}
	while( my $row=$sth->fetchrow_hashref ) {
		print $row->{ocrenty};
	}	
}
