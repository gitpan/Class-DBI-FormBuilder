package Class::DBI::FormBuilder;

use warnings;
use strict;
use Carp();

use List::Util();
use CGI::FormBuilder 3;

use UNIVERSAL::require;

# C::FB sometimes gets confused when passed CDBI::Column objects as field names, 
# hence all the map {''.$_} column filters. Some of them are probably unnecessary, 
# but I need to track down which.

our $VERSION = '0.344';

our @BASIC_FORM_MODIFIERS = qw( hidden options file );

our %ValidMap = ( varchar   => 'VALUE',
                  char      => 'VALUE', # includes MySQL enum and set
                  blob      => 'VALUE', # includes MySQL text
                  text      => 'VALUE',
                  
                  integer   => 'INT',
                  bigint    => 'INT',
                  smallint  => 'INT',
                  tinyint   => 'INT',
                  
                  date      => 'VALUE',
                  time      => 'VALUE',
                  
                  # normally you want to skip validating a timestamp column...
                  #timestamp => 'VALUE',
                  
                  double    => 'NUM',
                  float     => 'NUM',
                  decimal   => 'NUM',
                  numeric   => 'NUM',
                  );    
                  
sub import
{
    my ( $class, %args ) = @_;
    
    my $caller = caller(0);
    
    $caller->can( 'form_builder_defaults' ) || $caller->mk_classdata( 'form_builder_defaults', {} );
    
    my @export = qw( as_form 
                     search_form
                     
                     as_form_with_related
                     
                     update_or_create_from_form
                     
                     update_from_form_with_related
                     
                     retrieve_from_form
                     search_from_form 
                     search_like_from_form
                     search_where_from_form
                     
                     find_or_create_from_form 
                     retrieve_or_create_from_form
                     );
                   
    if ( $args{BePoliteToFromForm} )
    {
        no strict 'refs';
        *{"$caller\::${_}_fb"} = \&{"${_}_form"} for qw( update_from create_from );
    }
    else
    { 
        push @export, qw( update_from_form create_from_form );
    }
    
    no strict 'refs';
    *{"$caller\::$_"} = \&$_ for @export;
}

=head1 NAME

Class::DBI::FormBuilder - Class::DBI/CGI::FormBuilder integration

=head1 SYNOPSIS


    package Film;
    use strict;
    use warnings;
    
    use base 'Class::DBI';
    use Class::DBI::FormBuilder;
    
    # for automatic validation setup
    use Class::DBI::Plugin::Type;
    
    # POST all forms to server
    Film->form_builder_defaults( { method => 'post' } );
    
    # These fields must always be submitted for create/update routines
    Film->columns( Required => qw( foo bar ) );
    
    # same thing, differently
    # Film->form_builder_defaults->{required} = [ qw( foo bar ) ];
    
    
    # In a nearby piece of code...
    
    my $film = Film->retrieve( $id ); 
    print $film->as_form( params => $q )->render;   # or $r if mod_perl
    
    # For a search app:    
    my $search_form = Film->search_form;            # as_form plus a few tweaks
    
    
    # A fairly complete app:
    
    my $form = Film->as_form( params => $q );       # or $r if mod_perl
    
    if ( $form->submitted and $form->validate )
    {
        # whatever you need:
        
        my $obj = Film->create_from_form( $form );
        my $obj = Film->update_from_form( $form );              
        my $obj = Film->update_or_create_from_form( $form );    
        my $obj = Film->retrieve_from_form( $form );
        
        my $iter = Film->search_from_form( $form );
        my $iter = Film->search_like_from_form( $form );
        my $iter = Film->search_where_from_form( $form );
        
        my $obj = Film->find_or_create_from_form( $form );
        my $obj = Film->retrieve_or_create_from_form( $form );
        
        print $form->confirm;
    }
    else
    {
        print $form->render;
    }
    
    # See CGI::FormBuilder docs and website for lots more information.
    
=head1 DESCRIPTION

This module creates a L<CGI::FormBuilder|CGI::FormBuilder> form from a CDBI class or object. If 
from an object, it populates the form fields with the object's values. 

Column metadata and CDBI relationships are analyzed and the fields of the form are modified accordingly. 
For instance, MySQL C<enum> and C<set> columns are configured as C<select>, C<radiobutton> or 
C<checkbox> widgets as appropriate, and appropriate widgets are built for C<has_a>, C<has_many> 
and C<might_have> relationships. Further relationships can be added by subclassing.

A demonstration app (using L<Maypole::FormBuilder|Maypole::FormBuilder>) can be viewed at 

    http://beerfb.riverside-cms.co.uk

=head1 METHODS

All the methods described here are exported into the caller's namespace, except for the form modifiers 
(see below). 

=head2 Form generating methods

=over 4

=item form_builder_defaults( %args )

Stores default arguments for the call to C<CGI::FormBuilder::new()>.

=item as_form( %args )

Builds a L<CGI::FormBuilder|CGI::FormBuilder> form representing the class or object. 

Takes default arguments from C<form_builder_defaults>. 

The optional hash of arguments is the same as for C<CGI::FormBuilder::new()>, and will 
override any keys in C<form_builder_defaults>. 

Note that parameter merging is likely to become more sophisticated in future releases 
(probably copying the argument merging code from L<CGI::FormBuilder|CGI::FormBuilder> 
itself).

=cut

sub as_form
{
    my ( $proto, %args_in ) = @_;
    
    my ( $orig, %args ) = __PACKAGE__->_get_args( $proto, %args_in );
    
    __PACKAGE__->_setup_auto_validation( $proto, \%args );
    
    return __PACKAGE__->_make_form( $proto, $orig, %args );
}

=begin notes

It's impossible to know whether pk data are expected in the submitted data or not. For instance, 
while processing a form submission:
    
    my $form = My::Class->as_form;
    
    my $obj = My::Class->retrieve_from_form( $form );       # needs pk data
    my $obj = My::Class->find_or_create_from_form( $form ); # does not
    
pk hidden fields are always present in rendered forms, but may be empty (submits undef). undef does not 
pass validation tests. The solution is to place pk fields in 'keepextras', not in 'fields'. That means they 
are not validated at all. The only (I think) place submitted pk data are used is in retrieve_from_form

UPDATE: - the solution is probably to make pk fields optional, so they get validated if present.

=end notes

=cut

sub _get_args
{
    my ( $me, $proto, %args_in ) = @_;
    
    my %args = ( %{ $proto->form_builder_defaults }, %args_in );
    
    # take a copy, and make sure not to transform undef into []
    my $original_fields = $args{fields} ? [ @{ $args{fields} } ] : undef;
    
    my %pk = map { ''.$_ => 1 } $proto->primary_columns;
    
    $args{fields} ||= [ map  {''.$_} 
                        grep { ! $pk{ ''.$_ } }    
                        #$proto->columns( 'All' ) 
                        $me->_db_order_columns( $proto, 'All' )
                        ];
    
    # This is a bug, but the solution is to identify the list of required columns, and ensure 
    # pks are not included. Taht's non-trivial, because of the auto-validation funkiness.
    if ( exists( $args{keepextras} ) && ! ( ref( $args{keepextras} ) eq 'ARRAY' ) )
    {
        Carp::croak "keepextras can currently only support an arrayref of field names";
    }
    
    push( @{ $args{keepextras} }, keys %pk );
    
    # for objects, populate with data
    # nb. don't say $proto->get( $_ ) because $_ may be an accessor installed by a relationship 
    # (e.g. has_many) - get() only works with real columns.
    my @values = eval { map { '' . $proto->$_ } @{ $args{fields} } } if ref $proto;
    die "Error populating values for $proto from '@{ $args{fields} }': $@" if $@;
 
    $args{values} ||= \@values;
    
    my @reqd = map {''.$_} $proto->columns( 'Required' );
    
    if ( @reqd && ! $args{required} )
    {
        $args{required} = \@reqd;
    }
    
    # take care that anything in here is copied
    my $orig = { fields => $original_fields };
    
    return $orig, %args;
}

# Get deep into CDBI to extract the columns in the same order as defined in the database.
# In fact, this returns the columns in the order they were originally supplied to 
# $proto->columns( All => [ col list ] ). Defaults 
# to the order returned from the database query in CDBI::Loader, which for MySQL, 
# is the same as the order in the database.
sub _db_order_columns 
{
    my ( $me, $them, $group ) = @_;
    
    $group ||= 'All';
    
    return @{ $them->__grouper->{_groups}->{ $group } };
} 

sub _make_form
{
    my ( $me, $them, $orig, %args ) = @_;
    
    my $form = CGI::FormBuilder->new( %args );
    
    $form->{__cdbi_original_args__} = $orig;
    
    # this assumes meta_info only holds data on relationships
    foreach my $modify ( @BASIC_FORM_MODIFIERS, keys %{ $them->meta_info } ) 
    {
        my $form_modify = "form_$modify";
        
        $me->$form_modify( $them, $form );
    }
    
    return $form;
}

=item as_form_with_related

B<DEPRECATED>.

B<This method is NOT WORKING, and will be removed from a future version>. The plan is to replace C<as_form> 
with this code, when it's working properly. 

Builds a form with fields from the target CDBI class/object, plus fields from the related objects. 

Accepts the same arguments as C<as_form>, with these additions:

=over 4

=item related

A hashref of C<< $field_name => $as_form_args_hashref >> settings. Each C<$as_form_args_hashref> 
can take all the same settings as C<as_form>. These are used for generating the fields of the class or 
object(s) referred to by that field. For instance, you could use this to only display a subset of the 
fields of the related class. 

=item show_related

By default, all related fields are shown in the form. To only expand selected related fields, list 
them in C<show_related>.

=back

=cut

sub as_form_with_related
{
    my ( $proto, %args ) = @_;
    
    my $related_args = delete( $args{related} );
    my $show_related = delete( $args{show_related} ) || [];
    
    my $parent_form = $proto->as_form( %args );
    
    foreach my $field ( __PACKAGE__->_fields_and_has_many_accessors( $proto, $parent_form, $show_related ) )
    {
        # object or class
        my ( $related, $rel_type ) = __PACKAGE__->_related( $proto, $field );
        
        next unless $related;
        
        my @relateds = ref( $related ) eq 'ARRAY' ? @$related : ( $related );
        
        __PACKAGE__->_splice_form( $_, $parent_form, $field, $related_args->{ $field }, $rel_type ) for @relateds;
    }
    
    return $parent_form;
}

# deliberately ugly name to encourage something more generic in future
sub _fields_and_has_many_accessors
{
    my ( $me, $them, $form, $show_related ) = @_;
    
    return @$show_related if @$show_related;
    
    # Cleaning these out appears not to fix multiple pc fields, but also seems like the 
    # right thing to do. 
    my %pc = map { $_ => 1 } $them->primary_columns;
    
    my @fields = grep { ! $pc{ $_ } } $form->field;
    
    my %seen = map { $_ => 1 } @fields;
    
    my @related = keys %{ $them->meta_info( 'has_many' ) || {} };
    
    push @fields, grep { ! $seen{ $_ } } @related;
    
    return @fields;
}
        
# Add fields representing related class/object $them, to $parent_form, which represents 
# the class/object as_form_with_related was called on. E.g. add brewery, style, and many pubs 
# to a beer form. 
sub _splice_form
{
    my ( $me, $them, $parent_form, $field_name, $args, $rel_type ) = @_;
    
    # related pkdata are encoded in the fake field name
    warn 'not sure if pk for related objects is getting added - if so, it should not';
    
    warn "need to add 'add relatives' button";
    return unless ref $them; # for now
    
    my $related_form = $them->as_form( %$args );
    
    my $moniker = $them->moniker;
    
    my @related_fields;
    
    foreach my $related_field ( $related_form->fields )
    {
        my $related_field_name = $related_field->name;
        
        my $fake_name = $me->_false_related_field_name( $them, $related_field_name );
        
        $related_field->_form( $parent_form );
        
        $related_field->name( $fake_name );  
        
        $related_field->label( ucfirst( $moniker ) . ': ' . $related_field_name ) 
            unless $args->{labels}{ $related_field_name };
        
        $parent_form->{fieldrefs}{ $fake_name } = $related_field;
    
        push @related_fields, $related_field;
    }

    my $offset = 0;
    
    foreach my $parent_field ( $parent_form->fields )
    {
        $offset++;
        last if $parent_field->name eq $field_name;        
    }
    
    splice @{ $parent_form->{fields} }, $offset, 0, @related_fields;

    # different rel_types get treated differently e.g. is_a should probably not 
    # allow editing
    if ( $rel_type eq 'has_a' )
    {
        $parent_form->field( name => $field_name,
                             type => 'hidden',
                             );
    }
    elsif ( $rel_type eq 'is_a' )
    {
        $parent_form->field( name     => ''.$_,
                             readonly => 1,
                             )
                                for @related_fields;
    }
    
}
        
# Return the class or object(s) associated with a field, if anything is associated. 
sub _related
{
    my ( $me, $them, $field ) = @_;
    
    my ( $related_class, $rel_type ) = $me->_related_class_and_rel_type( $them, $field );
    
    return unless $related_class;
    
    return ( $related_class, $rel_type ) unless ref( $them );
    
    my $related_meta = $them->meta_info( $rel_type => $field ) ||
            die "No '$rel_type' meta for '$them', field '$field'";
    
    my $accessor = eval { $related_meta->accessor };    
    die "Can't find accessor in meta '$related_meta' for '$rel_type' field '$field' in '$them': $@" if $@;
    
    # multiple objects for has_many
    my @related_objects = $them->$accessor;
    
    return ( $related_class,      $rel_type ) unless @related_objects;
    return ( $related_objects[0], $rel_type ) if @related_objects == 1; 
    return ( \@related_objects,   $rel_type );
}

sub _related_class_and_rel_type
{
    my ( $me, $them, $field ) = @_;
    
    my @rel_types = keys %{ $them->meta_info };

    my $related_meta = List::Util::first { $_ } map { $them->meta_info( $_ => $field ) } @rel_types;
    
    return unless $related_meta;

    my $rel_type = $related_meta->name;
                  
    my $mapping = $related_meta->{args}->{mapping} || [];
    
    my $related_class;
 
    if ( @$mapping ) 
    {
        #use Data::Dumper;
        #my $foreign_meta = $related_meta->foreign_class->meta_info( 'has_a' );
        #die Dumper( [ $mapping, $rel_type, $related_meta, $foreign_meta ] );
        $related_class = $related_meta->foreign_class
                                      ->meta_info( 'has_a' )
                                      ->{ $$mapping[0] }
                                      ->foreign_class;
    
        my $accessor = $related_meta->accessor;   
        my $map = $$mapping[0];                        
    }
    else 
    {
        $related_class = $related_meta->foreign_class;
    }
    
    return ( $related_class, $rel_type );    
}

# ------------------------------------------------------- encode / decode field names -----
sub _false_related_field_name
{
    my ( $me, $them, $real_field_name ) = @_;
    
    my $class = $me->_encode_class( $them );
    my $pk    = $me->_encode_pk( $them );
    
    return $real_field_name . $class . $pk;
}

sub _real_related_field_name
{
    my ( $me, $field_name ) = @_;

    # remove any encoded class
    $field_name =~ s/CDBI_.+_CDBI//;
    
    # remove any primary keys
    $field_name =~ s/PKDATA_.+_PKDATA//;
    
    return $field_name;
}

sub _encode_pk
{
    my ( $me, $them ) = @_;
    
    return '' unless ref( $them );
    
    my @pk = map { $them->get( $_ ) } $them->primary_columns;
    
    die "dots in primary key values will confuse _encode_pk and _decode_pk"
        if grep { /\./ } @pk;
    
    my $pk = sprintf 'PKDATA_%s_PKDATA', join( '.', @pk );

    return $pk;
}

sub _decode_pk
{
    my ( $me, $fake_field_name ) = @_;
    
    return unless $fake_field_name =~ /PKDATA_(.+)_PKDATA/;
    
    my $pv = $1;
    
    my @pv = split /\./, $pv;
    
    my $class = $me->_decode_class( $fake_field_name );
    
    my @pc = map { ''.$_ } $class->primary_columns;
    
    my %pk = map { $_ => shift( @pv ) } @pc;
    
    return %pk;
}

sub _decode_class
{
    my ( $me, $fake_field_name ) = @_;

    $fake_field_name =~ /CDBI_(.+)_CDBI/;
    
    my $class = $1;
    
    $class || die "no class in fake field name $fake_field_name";
    
    $class =~ s/\./::/g;
    
    return $class;
}

sub _encode_class
{
    my ( $me, $them ) = @_;
    
    my $token = ref( $them ) || $them;
    
    $token =~ s/::/./g;
    
    return "CDBI_$token\_CDBI";   
}

sub _retrieve_entity_from_fake_fname
{
    my ( $me, $fake_field_name ) = @_;
    
    my $class = $me->_decode_class( $fake_field_name );
    
    my %pk = $me->_decode_pk( $fake_field_name );
    
    return $class unless %pk;
    
    my $obj = $class->retrieve( %pk );

    return $obj;
}

# ------------------------------------------------------- end encode / decode field names -----

=item search_form( %args )

Build a form with inputs that can be fed to search methods (e.g. C<search_where_from_form>). 
For instance, all selects are multiple, and fields that normally would be required 
are not. 

In many cases, you will want to design your own search form, perhaps only searching 
on a subset of the available columns. Note that you can acheive that by specifying 

    fields => [ qw( only these fields ) ]
    
in the args. 

The following search options are available. They are only relevant if processing 
via C<search_where_from_form>.

=over 4

=item search_opt_cmp

Allow the user to select a comparison operator by passing an arrayref:

    search_opt_cmp => [ ( '=', '!=', '<', '<=', '>', '>=', 
                          'LIKE', 'NOT LIKE', 'REGEXP', 'NOT REGEXP',
                          'REGEXP BINARY', 'NOT REGEXP BINARY',
                          ) ]
    

Or, transparently set the search operator in a hidden field:

    search_opt_cmp => 'LIKE'
    
=item search_opt_order_by

If true, will generate a widget to select (possibly multiple) columns to order the results by, 
with an C<ASC> and C<DESC> option for each column.

If set to an arrayref, will use that to build the widget. 

    # order by any columns
    search_opt_order_by => 1
    
    # or just offer a few
    search_opt_order_by => [ 'foo', 'foo DESC', 'bar' ]
    
=back

=cut

sub search_form
{
    my $proto = shift;
    
    my ( $orig, %args ) = __PACKAGE__->_get_args( $proto, @_ );
    
    my $form = __PACKAGE__->_make_form( $proto, $orig, %args );
    
    # make all selects multiple
    foreach my $field ( $form->field )
    {
        next unless exists $form->field->{ $field }; # this looks a bit suspect
        
        $field->multiple( 1 ) if $field->options;
                      
        $field->required( 0 );
    }   
    
    # ----- customise the search -----
    # For processing a submitted form, remember that the field _must_ be added to the form 
    # so that its submitted value can be extracted in search_where_from_form()
    
    # ----- order_by
    # this must come before adding any other fields, because the list of columns 
    # is taken from the form (not the CDBI class/object) so we match whatever 
    # column selection happened during form construction
    my %order_by_spec = ( name => 'search_opt_order_by',
                          multiple => 1,
                          );
    
    if ( my $order_by = delete $args{search_opt_order_by} )
    {
        $order_by = [ map  { $_, "$_ DESC" } 
                      grep { $_->type ne 'hidden' } 
                      $form->field 
                      ] 
                      unless ref( $order_by );
        
        $order_by_spec{options} = $order_by;
    }

    # ----- comparison operator    
    my $cmp = delete( $args{search_opt_cmp} ) || '=';
    
    my %cmp_spec = ( name => 'search_opt_cmp' );
    
    if ( ref( $cmp ) )
    {
        $cmp_spec{options}  = $cmp;
        $cmp_spec{value}    = $cmp->[0];
        $cmp_spec{multiple} = undef;
    }
    else
    {
        $cmp_spec{value} = $cmp;
        $cmp_spec{type}  = 'hidden';
    }

    $form->field( %cmp_spec );
    
    $form->field( %order_by_spec );    
    
    return $form;
}

=back

=head2 Form modifiers

These methods use CDBI's knowledge about its columns and table relationships to tweak the 
form to better represent a CDBI object or class. They can be overridden if you have better 
knowledge than CDBI does. For instance, C<form_options> only knows how to figure out 
select-type columns for MySQL databases. 

You can handle new relationship types by subclassing, and writing suitable C<form_*> methods (e.g. 
C<form_many_many)>. Your custom methods will be automatically called on the relevant fields. 

=over 4

=item form_hidden

Ensures primary column fields are included in the form (even if they were not included in the 
C<fields> list), and hides them.

=cut

# these fields are not in the 'fields' list, but are in 'keepextras'
sub form_hidden
{
    my ( $me, $them, $form ) = @_;
    
    foreach my $field ( map {''.$_} $them->primary_columns )
    {
        my $value = $them->get( $field ) if ref( $them );
        
        $form->field( name => $field,
                      type => 'hidden',
                      value => $value,
                      );
    }
}

=item form_options

Identifies column types that should be represented as select, radiobutton or 
checkbox widgets. Currently only works for MySQL C<enum> columns. 

There is a simple patch for L<Class::DBI::mysql|Class::DBI::mysql> that enables this for MySQL C<set> 
columns - see http://rt.cpan.org/NoAuth/Bug.html?id=12971

Patches are welcome for similar column types in other RDBMS's. 

Note that you can easily emulate a MySQL C<enum> column by setting the validation for the column 
to an arrayref of values. Haven't poked around yet to see how easily a C<set> column can 
be emulated.

=cut

sub form_options
{
    my ( $me, $them, $form ) = @_;
    
    foreach my $field ( map {''.$_} $them->columns('All') )
    {
        next unless exists $form->field->{ $field }; # $form->field( name => $field );
        
        my ( $series, $multiple ) = $me->_get_col_options_for_enumlike( $them, $field );
        
        next unless @$series;
        
        my $value = $them->get( $field ) if ref( $them );
        
        $form->field( name      => $field,
                      options   => $series,
                      multiple  => $multiple,
                      value     => $value,
                      );
    }    
}

# also used in _auto_validate
sub _get_col_options_for_enumlike
{
    my ( $me, $them, $col ) = @_;
    
    my ( @series, $multiple );

    CASE: {
        # MySQL enum
        last CASE if @series = eval { $them->enum_vals( $col ) };  
        # MySQL set
        $multiple++, last CASE if @series = eval { $them->set_vals( $col ) };
        
        # other dbs go here
    }
        
    return \@series, $multiple;
}

=item form_file

B<Unimplemented> - at the moment, you need to set the field type to C<file> manually. 

Figures out if a column contains file data. 

=cut

sub form_file
{
    my ( $me, $them, $form ) = @_;

    return;
}

=item form_has_a

Populates a select-type widget with entries representing related objects. Makes the field 
required.

Note that this list will be very long if there are lots of rows in the related table. 
You may need to override this method in that case. For instance, overriding with a 
no-op will result in a standard C<text> type input widget.

This method assumes the primary key is a single column - patches welcome. 

Retrieves every row and creates an object for it - not good for large tables.

If the relationship is to a non-CDBI class, loads a plugin to handle the field (see below - Plugins).

=cut

sub form_has_a
{
    my ( $me, $them, $form ) = @_;
    
    my $meta = $them->meta_info( 'has_a' ) || return;
    
    my @haves = keys %$meta;
    
    foreach my $field ( @haves ) 
    {
        #$me->_set_field_options( $them, $form, $field, { required => 1 } ) || next;
        next unless exists $form->field->{ $field };
        
        my ( $related_class, undef ) = $me->_related_class_and_rel_type( $them, $field );
        
        if ( $related_class->isa( 'Class::DBI' ) ) 
        {
            my $options = $me->_field_options( $them, $form, $field ) || 
                die "No options detected for field '$field'";
                
            my ( $related_object, $value );
            
            if ( ref $them )
            {
                $related_object = $them->get( $field ) || die sprintf
                'Failed to retrieve a related object from %s has_a field %s - inconsistent db?',
                    ref( $them ), $field;
                    
                my $pk = $related_object->primary_column;
                    
                $value = $related_object->$pk; 
            }
                
            $form->field( name     => $field,
                          options  => $options,
                          required => 1,
                          value    => $value,
                          );        
        } 
        else 
        {
            my $class = "Class::DBI::FormBuilder::Plugin::$related_class";
                        
            if ( $class->require )
            {
                $class->field( $them, $form, $field );
            }
#            elsif ( $@ =~ // ) XXX
#            {
#                # or simply stringify
#                $form->field( name     => $field,
#                              required => 1,
#                              value    => $them->$field.'',
#                              );        
#            }
            else
            {
                die "Failed to load $class: $@";
            }
        }        
        
    }
}

=begin notes

package Class::DBI::FormBuilder::Plugin::Time::Piece;
use strict;
use warnings FATAL => 'all';

#use Class::DBI::Plugin::Type; # not needed for mysql

# takes a list of stuff, calls/returns $form->field(%args)
#
sub field 
{
    my ( $class, $them, $form, $field ) = @_;

    my $type = $them->column_type( $field );

    my $value = $them->$field.''; # lousy default
    
    my $validate = undef;
    
    if ( $type eq 'time' ) 
    {
        $value = $them->$field->hms;
        
        $validate = '/\d\d:\d\d:\d\d/';
    } elsif ( $type eq 'date' ) 
    {
        $value = $them->$field->ymd;
        
        $validate = '/\d{4}-\d\d-\d\d/';
    } else 
    {
        die "don't understand column type '$type'";
    }
    
    $form->field( name      => $field,
                  value     => $value,
                  required  => 1,
                  validate  => $validate,
                  );
}

=end notes

=item form_has_many 

Also assumes a single primary column.

=cut

sub form_has_many
{
    my ( $me, $them, $form ) = @_;
    
    my $meta = $them->meta_info( 'has_many' ) || return;
    
    my @extras = keys %$meta;
    
    my %allowed = map { $_ => 1 } @{ $form->{__cdbi_original_args__}->{fields} || [ @extras ] };
    
    my @wanted = grep { $allowed{ $_ } } @extras;
    
    #$form->field( name => $_, multiple => 1 ) for @wanted;    
    
    # The target class/object ($them) does not have a column for the related class, 
    # so we need to add these to the form, then figure out their options.
    # Need to make sure and set some attribute to create the new field.
    # BUT - do not create the new field if it wasn't in the list passed in the original 
    # args, or if [] was passed in the original args. 
    
    foreach my $field ( @wanted )
    {
        # the 'next' condition is not tested because @wanted lists fields that probably 
        # don't exist yet, but should
        #next unless exists $form->field->{ $field };
        
        my $options = $me->_field_options( $them, $form, $field ) || 
            die "No options detected for '$them' field '$field'";
            
        my @many_pks;
        
        if ( ref $them )
        {
            my $rel = $meta->{ $field };
            
            my $accessor = $rel->accessor || die "no accessor for $field";
            
            my ( $related_class, undef ) = $me->_related_class_and_rel_type( $them, $field );
            die "no foreign_class for $field" unless $related_class;
            
            my $foreign_pk = $related_class->primary_column;
            
            # don't be tempted to access pks directly in $iter->data - they may refer to an 
            # intermediate table via a mapping method
            my $iter = $them->$accessor;
            
            while ( my $obj = $iter->next )
            {
                die "retrieved " . ref( $obj ) . " '$obj' is not a $related_class" 
                    unless ref( $obj ) eq $related_class;
                    
                push @many_pks, $obj->$foreign_pk;
            }
        }    
                      
        $form->field( name     => $field,
                      value    => \@many_pks,
                      options  => $options,
                      multiple => 1,
                      );
    }
}

=item form_might_have

Also assumes a single primary column.

=cut

# this code is almost identical to form_has_many
sub form_might_have
{
    my ( $me, $them, $form ) = @_;
    
    my $meta = $them->meta_info( 'might_have' ) || return;
    
    my @extras = keys %$meta;
    
    my %allowed = map { $_ => 1 } @{ $form->{__cdbi_original_args__}->{fields} || [ @extras ] };
    
    my @wanted = grep { $allowed{ $_ } } @extras;
    
    foreach my $field ( @wanted ) 
    {
        # the 'next' condition is not tested because @wanted lists fields that probably 
        # don't exist yet, but should
        
        my $options = $me->_field_options( $them, $form, $field ) || 
            die "No options detected for '$them' field '$field'";

        my $might_have_object_id;
        
        if ( ref $them )
        {        
            my $rel = $meta->{ $field };
            
            my $accessor = $rel->accessor || die "no accessor for $field";

            my ( $related_class, undef ) = $me->_related_class_and_rel_type( $them, $field );
            die "no foreign_class for $field" unless $related_class;
            
            my $foreign_pk = $related_class->primary_column;
                        
            my $might_have_object = $them->$accessor;
            
            if ( $might_have_object )
            {
                die "retrieved " . ref( $might_have_object ) . " '$might_have_object' is not a $related_class" 
                    unless ref( $might_have_object ) eq $related_class;
            }
            
            $might_have_object_id = $might_have_object ? $might_have_object->$foreign_pk : undef; # was ''
        }
        
        $form->field( name     => $field,
                      value    => $might_have_object_id,
                      options  => $options,
                      );
    }
}

sub _field_options
{
    my ( $me, $them, $form, $field ) = @_;
    
    my ( $related_class, undef ) = $me->_related_class_and_rel_type( $them, $field );
     
    return unless $related_class;
    
    return unless $related_class->isa( 'Class::DBI' );
    
    my $iter = $related_class->retrieve_all;
    
    my $pk = $related_class->primary_column;
    
    my @options;
    
    while ( my $object = $iter->next )
    {
        push @options, [ $object->$pk, ''.$object ];
    }
    
    return \@options;
}

=back

=head2 Form handling methods

B<Note>: if you want to use this module alongside L<Class::DBI::FromForm|Class::DBI::FromForm>, 
load the module like so

    use Class::DBI::FormBuilder BePoliteToFromForm => 1;
    
and the following 2 methods will instead be imported as C<create_from_fb> and C<update_from_fb>.

You might want to do this if you have more complex validation requirements than L<CGI::FormBuilder|CGI::FormBuilder> provides. 

All these methods check the form like this

    return unless $fb->submitted && $fb->validate;
    
which allows you to say things like

    print Film->update_from_form( $form ) ? $form->confirm : $form->render;
    
That's pretty concise!

=over 4

=item create_from_form( $form )

Creates and returns a new object.

=cut

sub create_from_form 
{
    my ( $class, $fb ) = @_;
    
    Carp::croak "create_from_form can only be called as a class method" if ref $class;
    
    return unless $fb->submitted && $fb->validate;
    
    return $class->create( __PACKAGE__->_fb_create_data( $class, $fb ) );
}

sub _fb_create_data
{
    my ( $me, $class, $fb ) = @_;
    
    my $cols = {};
    
    my $data = $fb->fields;
    
    foreach my $col ( map {''.$_} $class->columns('All') ) 
    {
        next unless exists $data->{ $col };
        
        $cols->{ $col } = $data->{ $col };
    }

    return $cols;
}

=begin crud

# If pk values are created in the database (e.g. in a MySQL AUTO_INCREMENT 
# column), then they will not be available in the new object. Neither will 
# anything else, because CDBI discards all data before returning the new 
# object. 
sub _create_object
{
    my ( $me, $class, $data ) = @_;
    
    die "_create_object needs a CDBI class, not an object" if ref( $class );
    
    my $obj = $class->create( $data );
    
    my @pcs = map { $obj->get( $_ ) } $obj->primary_columns;
    
    my $ok; 
    $ok &&= $_ for @pcs;
    
    return $obj if $ok; # every primary column has a value
    
    die "No pks for new object $obj" unless @pcs == 1; # 1 undef value - we can find it
    
    # this works for MySQL and SQLite - these may be the only dbs that don't 
    # supply the pk data in the first place?
    my $id = $obj->_auto_increment_value;
    
    return $class->retrieve( $id ) || die "Could not retrieve newly created object with ID '$id'";
}

=end crud

=item update_from_form( $form )

Updates an existing CDBI object. 

If called on an object, will update that object.

If called on a class, will first retrieve the relevant object (via C<retrieve_from_form>).

=cut

sub update_from_form 
{
    my $proto = shift;
    
    my $them = ref( $proto ) ? $proto : $proto->retrieve_from_form( @_ );
    
    Carp::croak "No object found matching submitted primary key data" unless $them;
    
    __PACKAGE__->_run_update( $them, @_ );
}

sub _run_update 
{
    my ( $me, $them, $fb ) = @_;
    
    return unless $fb->submitted && $fb->validate;
    
    my $formdata = $fb->fields;
    
    # I think this is now unnecessary (0.4), because pks are in keepextras
    delete $formdata->{ $_ } for map {''.$_} $them->primary_columns;
    
    # assumes no extra fields in the form
    #$them->set( %$formdata );
    
    # Start with all possible columns. Only ask for the subset represented 
    # in the form. This allows correct handling of fields that result in 
    # 'missing' entries in the submitted data - e.g. checkbox groups with 
    # no item selected will not even appear in the raw request data, but here
    # they should result in an undef value being sent to the object.
    my %coldata = map  { $_ => $formdata->{ $_ } } 
                  grep { exists $formdata->{ $_ } }
                  $them->columns( 'All' );
    
    $them->set( %coldata );
    
    $them->update;
    
    return $them;
}

=item update_from_form_with_related

Sorry about the name, alternative suggestions welcome.

=cut

sub update_from_form_with_related
{
    my ( $proto, $form ) = @_;
    
    my $them = ref( $proto ) ? $proto : $proto->retrieve_from_form( $form );
    
    Carp::croak "No object found matching submitted primary key data" unless $them;
    
    Carp::croak "Still not an object: $them" unless ref( $them );
    
    die "Not a form: $form" unless $form->isa( 'CGI::FormBuilder' );
    
    __PACKAGE__->_run_update_from_form_with_related( $them, $form );
}

sub _run_update_from_form_with_related
{
    my ( $me, $them, $fb ) = @_;
    
    return unless $fb->submitted && $fb->validate;
    
    # Don't think about relationships. We have form data that can be associated 
    # with specific objects in different classes, or with the creation of new 
    # objects in different classes. Just decode the form field names, collect 
    # each set of data, and send to CDBI 
    
    my $struct = $me->_extract_data_from_form_with_related( $fb );
    
    # entries are class names or PARENT, entities are class names or objects
    # (or no entity for PARENT)
    foreach my $entry ( keys %$struct )
    {
        my $formdata = $struct->{ $entry }->{data};
        my $entity   = $struct->{ $entry }->{entity}; 
        
        # the parent object has no entity in $struct
        $entity ||= $them;
    
        # Start with all possible columns. Only ask for the subset represented 
        # in the form. This allows correct handling of fields that result in 
        # 'missing' entries in the submitted data - e.g. checkbox groups with 
        # no item selected will not even appear in the raw request data, but here
        # they should result in an undef value being sent to the object.
        my %coldata = map  { $_ => $formdata->{ $_ } } 
                      grep { exists $formdata->{ $_ } }
                      $entity->columns( 'All' );
    
        if ( ref $entity )
        {   # update something that already exists
        
            # XXX hack - this stuff should not be in the form, or should be in cgi_params (maybe)
            my %pk = map { $_ => 1 } $entity->primary_columns;
            my $found_pk = 0;
            $found_pk++ for grep { $pk{ $_ } } keys %coldata;
            warn sprintf( "Got pk data for '%s' (%s) in formdata", $entity, ref( $entity ) ) 
                if $found_pk;
            delete $coldata{ $_ } for keys %pk;
        
            $entity->set( %coldata );
            
            $entity->update;
        }
        else
        {   # create something new
            my $class = $entity;
            
            $entity = $class->create( \%coldata );
            
            # just for tidiness - probably not going to need to keep the struct
            #$struct->{ $entity } = delete $struct->{ $class };
            
            # relate it to parent
            $me->_setup_relationships_between( $them, $entity ) || 
                die "failed to set up any relationships between parent '$them' and new object '$entity'";
            
        }
    }
    
    return $them;
}

sub _extract_data_from_form_with_related
{
    my ( $me, $fb ) = @_;

    my $formdata = $fb->fields;
    
    my $struct;
    
    foreach my $field ( keys %$formdata )
    {
        my $real_field_name = $me->_real_related_field_name( $field );
        
        if ( $real_field_name eq $field )
        {
            $struct->{PARENT}{data}{ $field } = $formdata->{ $field };
            #$struct->{ ref $them }{entity} ||= $them;
        }
        else
        {
            # class or object
            my $related = $me->_retrieve_entity_from_fake_fname( $field );
            
            my $related_class = ref( $related ) || $related;
            
            $struct->{ $related_class }{data}{ $real_field_name } = $formdata->{ $field };
            $struct->{ $related_class }{entity} ||= $related;
        }
    }
    
    return $struct;
}

=begin previously

# $them is either the parent object, or a related object or class. 
# Make sure the parent doesn't get transformed into a class.
sub _extract_data_from_form_with_related
{
    my ( $me, $them, $fb ) = @_;

    my $formdata = $fb->fields;
    
    my %pk = map { $_ => 1 } $them->primary_columns;
    
    my $struct;
    
    foreach my $field ( keys %$formdata )
    {
        my $real_field_name = $me->_real_related_field_name( $field );
        
        warn "Got pk data (field '$real_field_name' as '$field') for $them in formdata" 
            if $pk{ $real_field_name };
        
        next if $pk{ $real_field_name };
        
        if ( $real_field_name eq $field )
        {
            $struct->{ ref $them }{data}{ $field } = $formdata->{ $field };
            $struct->{ ref $them }{entity} ||= $them;
        }
        else
        {
            # class or object
            my $related = $me->_retrieve_entity_from_fake_fname( $field );
            
            my $related_class = ref( $related ) || $related;
            
            $struct->{ $related_class }{data}{ $real_field_name } = $formdata->{ $field };
            $struct->{ $related_class }{entity} ||= $related;
        }
    }
    
    return $struct;
}

=end previously

=cut

# I'm nervous that I can create an object and *then* set up its relationships, 
# but that seems to be the easiest way to go:

# create new object
# inspect its meta for relationships back to the parent
#   if there are any, get the mutator from the meta
#   call the mutator with the parent as argument
# then inspect the parent's meta for relationships to the new object
#   if there are any, get the mutator from the meta
#   call the mutator with the child as argument
sub _setup_relationships_between
{
    my ( $me, $them, $related ) = @_;
    
    die "root object must be an object - got $them"       unless ref( $them );
    die "related object must be an object - got $related" unless ref( $related );
    
    my $made_rels = 0;
    
    foreach my $meta_accessor ( $me->_meta_accessors( $related ) )
    {
        my ( $related_class, $rel_type ) = $me->_related_class_and_rel_type( $related, $meta_accessor );
        
        next unless $related_class && ( ref( $them ) eq $related_class );
        
        $related->$meta_accessor( $them );
        
        $made_rels++;
        
        last;
    }
    
    foreach my $meta_accessor ( $me->_meta_accessors( $them ) )
    {
        my ( $related_class, $rel_type ) = $me->_related_class_and_rel_type( $them, $meta_accessor );
        
        next unless $related_class && ( ref( $related ) eq $related_class );
        
        $them->$meta_accessor( $related );
        
        $made_rels++;
        
        last;
    }            
    
    return $made_rels;
}

# like columns( 'All' ), but only for things in meta - so includes has_many accessors, 
# which don't occur in columns( 'All' ) 
sub _meta_accessors
{
    my ( $me, $them ) = @_;
    
    my @accessors;
    
    foreach my $rel_type ( keys %{ $them->meta_info } )
    {
        push @accessors, keys %{ $them->meta_info( $rel_type ) };
    }

    return @accessors;
}

=item update_or_create_from_form

Class method.

Attempts to look up an object (using primary key data submitted in the form) and update it. 

If none exists (or if no values for primary keys are supplied), a new object is created. 

=cut

sub update_or_create_from_form
{
    my $class = shift;
    
    Carp::croak "update_or_create_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_update_or_create_from_form( $class, @_ );
}

sub _run_update_or_create_from_form
{
    my ( $me, $them, $fb ) = @_;

    return unless $fb->submitted && $fb->validate;

    #my $formdata = $fb->fields;

    my $object = $them->retrieve_from_form( $fb );
    
    return $object->update_from_form( $fb ) if $object;
    
    $them->create_from_form( $fb );
}

=back

=head2 Search methods

Note that search methods (except for C<retrieve_from_form>) will return a CDBI iterator 
in scalar context, and a (possibly empty) list of objects in list context.

All the search methods except C<retrieve_from_form> require that the submitted form should either be built using 
C<search_form> (not C<as_form>), or should supply all C<required> (including C<has_a>) fields. 
Otherwise they may fail validation checks for missing required fields. 

=over 4

=item retrieve_from_form

Use primary key data in a form to retrieve a single object.

=cut

sub retrieve_from_form
{
    my $class = shift;
    
    Carp::croak "retrieve_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_retrieve_from_form( $class, @_ );
}

sub _run_retrieve_from_form
{
    my ( $me, $them, $fb ) = @_;
    
    # we don't validate because pk data must side-step validation as it's 
    # unknowable in advance whether they will even be present. 
    #return unless $fb->submitted && $fb->validate;
    
    my %pkdata = map { $_ => $fb->cgi_param( ''.$_ ) || undef } $them->primary_columns;
    
    return $them->retrieve( %pkdata );
}

=item search_from_form

Lookup by column values.

=cut

sub search_from_form 
{
    my $class = shift;
    
    Carp::croak "search_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_search_from_form( $class, '=', @_ );
}

=item search_like_from_form

Allows wildcard searches (% or _).

Note that the submitted form should be built using C<search_form>, not C<as_form>. 

=cut

sub search_like_from_form
{
    my $class = shift;
    
    Carp::croak "search_like_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_search_from_form( $class, 'LIKE', @_ );
}

sub _run_search_from_form
{    
    my ( $me, $them, $search_type, $fb ) = @_;
    
    return unless $fb->submitted && $fb->validate;

    my %searches = ( LIKE => 'search_like',
                     '='  => 'search',
                     );
                     
    my $search_method = $searches{ $search_type };
    
    my @search = $me->_get_search_spec( $them, $fb );
    
    # Probably you would normally sort results in the output page, rather 
    # than in the search form. Might be useful to specify the initial sort order 
    # in a hidden 'sort_by' field.
    my @modifiers = qw( order_by order_direction ); # others too
    
    my %search_modifiers = $me->_get_search_spec( $them, $fb, \@modifiers );
    
    push( @search, \%search_modifiers ) if %search_modifiers;
    
    return $them->$search_method( @search );
}

sub _get_search_spec
{
    my ( $me, $them, $fb, $fields ) = @_;

    my @fields = $fields ? @$fields : $them->columns( 'All' );

    # this would miss multiple items
    #my $formdata = $fb->fields;
    
    my $formdata;
    
    foreach my $field ( $fb->fields )
    {
        my @data = $field->value;
        
        $formdata->{ $field } = @data > 1 ? \@data : $data[0];
    }
    
    return map  { $_ => $formdata->{ $_ } } 
           grep { defined $formdata->{ $_ } } # don't search on unsubmitted fields
           @fields;
}

=item search_where_from_form

L<Class::DBI::AbstractSearch|Class::DBI::AbstractSearch> must be loaded in your 
CDBI class for this to work.

If no search terms are specified, then the search 

    WHERE 1 = 1
    
is executed (returns all rows), no matter what search operator may have been selected.

=cut

sub search_where_from_form
{
    my $class = shift;
    
    Carp::croak "search_where_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_search_where_from_form( $class, @_ );
}

# have a look at Maypole::Model::CDBI::search()
sub _run_search_where_from_form
{
    my ( $me, $them, $fb ) = @_;
    
    return unless $fb->submitted && $fb->validate;

    my %search_data = $me->_get_search_spec( $them, $fb );
    
    # clean out empty fields
    do { delete( $search_data{ $_ } ) unless $search_data{ $_ } } for keys %search_data;
    
    # these match fields added in search_form()
    my %modifiers = ( search_opt_cmp      => 'cmp', 
                      search_opt_order_by => 'order_by',
                      );
    
    my %search_modifiers = $me->_get_search_spec( $them, $fb, [ keys %modifiers ] );
    
    # rename modifiers for SQL::Abstract - taking care not to autovivify entries
    $search_modifiers{ $modifiers{ $_ } } = delete( $search_modifiers{ $_ } ) 
        for grep { $search_modifiers{ $_ } } keys %modifiers;
    
    # return everything if no search terms specified
    unless ( %search_data )
    {
        $search_data{1}        = 1;
        $search_modifiers{cmp} = '=';
    }
    
    my @search = %search_modifiers ? ( \%search_data, \%search_modifiers ) : %search_data;
    
    return $them->search_where( @search );
}

=item find_or_create_from_form

Does a C<find_or_create> using submitted form data. 

=cut
    
sub find_or_create_from_form
{
    my $class = shift;
    
    Carp::croak "find_or_create_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_find_or_create_from_form( $class, @_ );
}

sub _run_find_or_create_from_form
{
    my ( $me, $them, $fb ) = @_;

    return unless $fb->submitted && $fb->validate;

    my %search_data = $me->_get_search_spec( $them, $fb );
    
    return $them->find_or_create( \%search_data );    
}

=item retrieve_or_create_from_form

Attempts to look up an object. If none exists, a new object is created. 

This is similar to C<update_or_create_from_form>, except that this method will not 
update pre-existing objects. 

=cut

sub retrieve_or_create_from_form
{
    my $class = shift;
    
    Carp::croak "retrieve_or_create_from_form can only be called as a class method" if ref $class;

    __PACKAGE__->_run_retrieve_or_create_from_form( $class, @_ );
}

sub _run_retrieve_or_create_from_form
{
    my ( $me, $them, $fb ) = @_;

    return unless $fb->submitted && $fb->validate;

    my $object = $them->retrieve_from_form( $fb );
    
    return $object if $object;
    
    $them->create_from_form( $fb );
}


=back

=head1 Automatic validation setup

If you place a normal L<CGI::FormBuilder|CGI::FormBuilder> validation spec in 
C<< $class->form_builder_defaults->{validate} >>, that spec will be used to configure validation. 

If there is no spec in C<< $class->form_builder_defaults->{validate} >>, then validation will 
be configured automatically. The default configuration is pretty basic, but you can modify it 
by placing settings in C<< $class->form_builder_defaults->{auto_validate} >>. 

You must load L<Class::DBI::Plugin::Type|Class::DBI::Plugin::Type> in your class if using automatic 
validation.

=over 4

=item Basic auto-validation

Given no validation options for a column in the C<auto_validate> slot, the settings for most columns 
will be taken from C<%Class::DBI::FormBuilder::ValidMap>. This maps SQL column types (as supplied by 
L<Class::DBI::Plugin::Type|Class::DBI::Plugin::Type>) to the L<CGI::FormBuilder|CGI::FormBuilder> validation 
settings C<VALUE>, C<INT>, or C<NUM>. 

MySQL C<ENUM> or C<SET> columns will be set up to validate that the submitted value(s) match the allowed 
values (although C<SET> column functionality requires the patch to CDBI::mysql mentioned above). 

Any column listed in C<< $class->form_builder_defaults->{options} >> will be set to validate those values. 

=item Advanced auto-validation

The following settings can be placed in C<< $class->form_builder_defaults->{auto_validate} >>.

=over 4

=item validate

Specify validate types for specific columns:

    validate => { username   => [qw(nate jim bob)],
                  first_name => '/^\w+$/',    # note the 
                  last_name  => '/^\w+$/',    # single quotes!
                  email      => 'EMAIL',
                  password   => \&check_password,
                  confirm_password => {
                      javascript => '== form.password.value',
                      perl       => 'eq $form->field("password")'
                  }
                          
This option takes the same settings as the C<validate> option to C<CGI::FormBuilder::new()> 
(i.e. the same as would otherwise go in C<< $class->form_builder_defaults->{validate} >>). 
Settings here override any others. 

=item skip_columns

List of columns that will not be validated:

    skip_columns => [ qw( secret_stuff internal_data ) ]

=item match_columns

Use regular expressions matching groups of columns to specify validation:

    match_columns => { qr/(^(widget|burger)_size$/ => [ qw( small medium large ) ],
                       qr/^count_.+$/             => 'INT',
                       }
                       
=item validate_types

Validate according to SQL data types:

    validate_types => { date => \&my_date_checker,
                       }
                       
Defaults are taken from the package global C<%TypesMap>. 
                        
=item match_types

Use a regular expression to map SQL data types to validation types:

    match_types => { qr(date) => \&my_date_checker,
                     }
                     
=item debug
    
Control how much detail to report (via C<warn>) during setup. Set to 1 for brief 
info, and 2 for a list of each column's validation setting.

=item strict

If set to 1, will die if a validation setting cannot be determined for any column. 
Default is to issue warnings and not validate these column(s).
    
=back

=item Validating relationships

Although it would be possible to retrieve the IDs of all objects for a related column and use these to 
set up validation, this would rapidly become unwieldy for larger tables. Default validation will probably be 
acceptable in most cases, as the column type will usually be some kind of integer. 

=item timestamp

The default behaviour is to skip validating C<timestamp> columns. A warning will be issued
if the C<debug> parameter is set to 2.

=item Failures

The default mapping of column types to validation types is set in C<%Class::DBI::FormBulder::ValidMap>, 
and is probably incomplete. If you come across any failures, you can add suitable entries to the hash before calling C<as_form>. However, B<please> email me with any failures so the hash can be updated for everyone.

=back

=cut

sub _get_type
{
    my ( $me, $them, $col ) = @_;
    
    my $type = $them->column_type( $col );
    
    die "No type detected for column $col in $them" unless $type;
        
    # $type may be something like varchar(255)
    
    $type =~ s/[^a-z]*$//;

    return $type;
}
                  
sub _valid_map
{
    my ( $me, $type ) = @_;
    
    return $ValidMap{ $type };
}

sub _setup_auto_validation 
{
    my ( $me, $them, $fb_args ) = @_;
    
    # $fb_args is the args hash that will be sent to CGI::FB to construct the form. 
    # Here we re-write $fb_args->{validate}
    
    my %args = $me->_get_auto_validate_args( $them );
     
    return unless %args;
    
    warn "auto-validating $them\n" if $args{debug};
    
    #warn "fb_args:" . Dumper( $fb_args );
    
    my $v_cols        = $args{validate}         || {}; 
    my $skip_cols     = $args{skip_columns}     || [];
    my $match_cols    = $args{match_columns}    || {}; 
    my $v_types       = $args{validate_types}   || {}; 
    my $match_types   = $args{match_types}      || {}; 
    
    my %skip = map { $_ => 1 } @$skip_cols;
    
    my %validate; 
    
    # $col->name preserves case - stringifying doesn't
    foreach my $col ( @{ $fb_args->{fields} } ) 
    {
        next if $skip{ $col };    
        
        # this will get added at the end
        next if $v_cols->{ $col }; 
        
        # look for columns with options
        # TODO - what about related columns? - do not want to add 10^6 db rows to validation
             
        my $options = $them->form_builder_defaults->{options} || {};
        
        my $o = $options->{ $col };
        
        unless ( $o )
        {
            my ( $series, undef ) = $me->_get_col_options_for_enumlike( $them, $col );
            $o = $series; 
            warn "(Probably) setting validation to options (@$o) for $col in $them" if ( $args{debug} > 1 and @$o );
            undef( $o ) unless @$o;            
        }
        
        my $type = $me->_get_type( $them, $col );
        
        my $v = $o || $v_types->{ $type }; 
                 
        foreach my $regex ( keys %$match_types )
        {
            last if $v;
            $v = $match_types->{ $regex } if $type =~ $regex;
        }
        
        foreach my $regex ( keys %$match_cols )
        {
            last if $v;
            $v = $match_cols->{ $regex } if $col =~ $regex;
        }
        
        my $skip_ts = ( ( $type eq 'timestamp' ) && ! $v );
        
        warn "Skipping $them $col [timestamp]\n" if ( $skip_ts and $args{debug} > 1 );
        
        next if $skip_ts;
        
        $v ||= $me->_valid_map( $type ) || '';
        
        my $fail = "No validate type detected for column $col, type $type in $them"
            unless $v;
            
        $fail and $args{strict} ? die $fail : warn $fail;
    
        my $type2 = substr( $type, 0, 25 );
        $type2 .= '...' unless $type2 eq $type;
        
        warn sprintf "Untainting %s %s [%s] as %s\n", $them, $col, $type2, $v
                if $args{debug} > 1;
        
        $validate{ $col } = $v if $v;
    }
    
    my $validation = { %validate, %$v_cols };
    
    if ( $args{debug} > 1 )
    {
        Data::Dumper->require;
        warn "Setting up validation: " . Data::Dumper::Dumper( $validation );
    }
    
    $fb_args->{validate} = $validation;
    
    return;
}

sub _get_auto_validate_args
{
    my ( $me, $them ) = @_;
    
    my $fb_defaults = $them->form_builder_defaults;
    
    if ( %{ $fb_defaults->{validate} || {} } && %{ $fb_defaults->{auto_validate} || {} } )
    {
        die "Got validation AND auto-validation settings in form_builder_defaults (should only have one or other)";
    }
    
    return if %{ $fb_defaults->{validate} || {} };
    
    #use Data::Dumper;
    #warn "automating with config " . Dumper( $fb_defaults->{auto_validate} );
    
    # stop lots of warnings, and ensure something is set so the cfg exists test passes
    $fb_defaults->{auto_validate}->{debug} ||= 0;
    
    return %{ $fb_defaults->{auto_validate} };
}

=head1 Plugins

C<has_a> relationships can refer to non-CDBI classes. In this case, C<form_has_a> will attempt to 
load (via C<require>) an appropriate plugin. For instance, for a C<Time::Piece> column, it will attempt 
to load C<Class::DBI::FormBuilder::Plugin::Time::Piece>. Then it will call the C<field> method in the plugin, passing 
the CDBI class for whom the form has been constructed, the form, and the name of the field being processed. 
The plugin can use this information to modify the form, perhaps adding extra fields, or controlling 
stringification, or setting up custom validation. 

If no plugin is found, a fatal exception is raised. If you have a situation where it would be useful to 
simply stringify the object instead, let me know and I'll make this configurable.

=head1 TODO

Better merging of attributes. For instance, it'd be nice to set some field attributes 
(e.g. size or type) in C<form_builder_defaults>, and not lose them when the fields list is 
generated and added to C<%args>. 

Store CDBI errors somewhere on the form. For instance, if C<update_from_form> fails because 
no object could be retrieved using the form data. 

Detect binary data and build a file upload widget. 

C<is_a> relationships.

C<enum> and C<set> equivalent column types in other dbs.

Think about non-CDBI C<has_a> inflation/deflation. In particular, maybe there's a Better 
Way than subclassing to add C<form_*> methods. For instance, adding a date-picker widget 
to deal with DateTime objects. B<UPDATE>: the new plugin architecture added in 0.32 should 
handle this.

Figure out how to build a form for a related column when starting from a class, not an object
(pointed out by Peter Speltz). E.g. 

   my $related = $object->some_col;

   print $related->as_form->render;
   
will not work if $object is a class. Have a look at Maypole::Model::CDBI::related_class. 

Integrate fields from a related class object into the same form (e.g. show address fields 
in a person form, where person has_a address). B<UPDATE>: fairly well along in 0.32 (C<as_form_with_related>).

C<_splice_form> needs to handle custom setup for more relationship types. 

=head1 AUTHOR

David Baird, C<< <cpan@riverside-cms.co.uk> >>

=head1 BUGS

Do not set C<keepextras> to 1. You must set it to a list of field names. 

Please report any bugs or feature requests to
C<bug-class-dbi-plugin-formbuilder@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-DBI-FormBuilder>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

Looking at the code (0.32), I suspect updates to has_many accessors are not implemented, since the update
methods only fetch data for columns( 'All' ), which doesn't include has_many accessors/mutators. 

=head1 ACKNOWLEDGEMENTS

James Tolley for providing the plugin code.

=head1 COPYRIGHT & LICENSE

Copyright 2005 David Baird, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Class::DBI::Plugin::FormBuilder

__END__

Example of a dumped CDBI meta_info structure for BeerDB::Beer:

$VAR1 = {
          'has_a' => {
                       'style' => bless( {
                                           'foreign_class' => 'BeerFB::Style',
                                           'name' => 'has_a',
                                           'args' => {},
                                           'class' => 'BeerFB::Beer',
                                           'accessor' => bless( {
                                                                  '_groups' => {
                                                                                 'All' => 1
                                                                               },
                                                                  'name' => 'style',
                                                                  'mutator' => 'style',
                                                                  'placeholder' => '?',
                                                                  'accessor' => 'style'
                                                                }, 'Class::DBI::Column' )
                                         }, 'Class::DBI::Relationship::HasA' ),
                       'brewery' => bless( {
                                             'foreign_class' => 'BeerFB::Brewery',
                                             'name' => 'has_a',
                                             'args' => {},
                                             'class' => 'BeerFB::Beer',
                                             'accessor' => bless( {
                                                                    '_groups' => {
                                                                                   'All' => 1
                                                                                 },
                                                                    'name' => 'brewery',
                                                                    'mutator' => 'brewery',
                                                                    'placeholder' => '?',
                                                                    'accessor' => 'brewery'
                                                                  }, 'Class::DBI::Column' )
                                           }, 'Class::DBI::Relationship::HasA' )
                     },
          'has_many' => {
                          'pubs' => bless( {
                                             'foreign_class' => 'BeerFB::Handpump',
                                             'name' => 'has_many',
                                             'args' => {
                                                         'mapping' => [
                                                                        'pub'
                                                                      ],
                                                         'foreign_key' => 'beer',
                                                         'order_by' => undef
                                                       },
                                             'class' => 'BeerFB::Beer',
                                             'accessor' => 'pubs'
                                           }, 'Class::DBI::Relationship::HasMany' )
                        }
        };


And for BeerFB::Pub:

$VAR1 = {
          'has_many' => {
                          'beers' => bless( {
                                              'foreign_class' => 'BeerFB::Handpump',
                                              'name' => 'has_many',
                                              'args' => {
                                                          'mapping' => [
                                                                         'beer'
                                                                       ],
                                                          'foreign_key' => 'pub',
                                                          'order_by' => undef
                                                        },
                                              'class' => 'BeerFB::Pub',
                                              'accessor' => 'beers'
                                            }, 'Class::DBI::Relationship::HasMany' )
                        }
        };

And for BeerFB::Handpump:

$VAR1 = {
          'has_a' => {
                       'pub' => bless( {
                                         'foreign_class' => 'BeerFB::Pub',
                                         'name' => 'has_a',
                                         'args' => {},
                                         'class' => 'BeerFB::Handpump',
                                         'accessor' => bless( {
                                                                'name' => 'pub',
                                                                '_groups' => {
                                                                               'All' => 1
                                                                             },
                                                                'mutator' => 'pub',
                                                                'placeholder' => '?',
                                                                'accessor' => 'pub'
                                                              }, 'Class::DBI::Column' )
                                       }, 'Class::DBI::Relationship::HasA' ),
                       'beer' => bless( {
                                          'foreign_class' => 'BeerFB::Beer',
                                          'name' => 'has_a',
                                          'args' => {},
                                          'class' => 'BeerFB::Handpump',
                                          'accessor' => bless( {
                                                                 'name' => 'beer',
                                                                 '_groups' => {
                                                                                'All' => 1
                                                                              },
                                                                 'mutator' => 'beer',
                                                                 'placeholder' => '?',
                                                                 'accessor' => 'beer'
                                                               }, 'Class::DBI::Column' )
                                        }, 'Class::DBI::Relationship::HasA' )
                     }
        };



