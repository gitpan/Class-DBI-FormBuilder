#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Test::Exception;

if ( ! DBD::SQLite2->require ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

plan tests => 3;

use DBI::Test; # also includes Bar

$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'id=1&_submitted=1';

my $dbaird = Person->retrieve( 1 );

my $data = { street => 'NiceStreet',
             name   => 'DaveBaird',
             town   => 'Trumpton',
             toys    => undef,
             };        

my $obj_data = { map { $_ => $dbaird->$_ || undef } keys %$data };
is_deeply( $obj_data, $data );

my $form_from_class  = Person->as_form( selectnum => 2 );
my $form_from_object = $dbaird->as_form( selectnum => 2 );

my $html_from_class  = $form_from_class->render;
my $html_from_object = $form_from_object->render;

# select, no option selected
# This was failing in first version, due to testing for $form->field( name => $field ); 
# instead of the existence of the field (the former returns its value, which is empty 
# in classes)
diag("SQLite is typeless, hence n/a options (all columns are nullable)");
like( $html_from_class, qr(<select id="town" name="town"><option value="">-select-</option><option>n/a</option><option value="1">Trumpton</option><option value="2">Uglyton</option><option value="3">Toonton</option><option value="4">London</option></select>), 'finding has_a rels' );

# select, option 1 selected
like( $html_from_object, qr(<select id="town" name="town"><option value="">-select-</option><option>n/a</option><option selected="selected" value="1">Trumpton</option><option value="2">Uglyton</option><option value="3">Toonton</option><option value="4">London</option></select>), 'finding has_a rels' );


#use Data::Dumper;
#warn Dumper( $dbaird->meta_info );
#warn Dumper( Bar->meta_info );

