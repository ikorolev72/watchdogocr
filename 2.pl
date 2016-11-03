#!/usr/bin/perl
use lib "/home/directware/watchdogocr/"; 
use watchdogocr_common;
$a='/home/directware/watchdogocr/var/tmp/293328 paystub_ID51_PAGE3.txt';
$b=ReadFile( $a );
print $b;