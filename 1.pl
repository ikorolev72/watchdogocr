use watchdogocr_common;

my $prefix=get_prefix( '292283personalchecking_PAGE5.pdf' );
my $filename_ocr="${prefix}_ocr.pdf";

my ( $prefix_master , $page )=get_prefix_page( '292283personalchecking_PAGE5.pdf' );

print "$filename_ocr\n$prefix\n$prefix_master\n$page\n";
