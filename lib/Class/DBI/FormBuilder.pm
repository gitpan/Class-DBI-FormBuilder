package Class::DBI::FormBuilder;

use warnings;
use strict;
use Carp();

# not sure if I need to insist on 3
use CGI::FormBuilder; # 3;

# C::FB sometimes gets confused when passed CDBI::Column objects as field names, 
# hence all the map {''.$_} column filters. Some of them are probably unnecessary, 
# but I need to track down which.

our $VERSION = 0.2;

sub import
{
    my ( $class, %args ) = @_;
    
    my $caller = caller(0);
    
    $caller->can( 'form_builder_defaults' ) || $caller->mk_classdata( 'form_builder_defaults', {} );
    
    my @export = qw( as_form 
                     search_form
                     
                     update_or_create_from_form
                     
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
    my $proto = shift;
    
    my ( $orig, %args ) = __PACKAGE__->_get_args( $proto, @_ );
    
    return __PACKAGE__->_make_form( $proto, $orig, %args );
}

sub _get_args
{
    my ( $me, $proto ) = ( shift, shift );
    
    my %args = ( %{ $proto->form_builder_defaults }, @_ );
    
    # take a copy, and make sure not to transform undef into []
    my $original_fields = $args{fields} ? [ @{ $args{fields} } ] : undef;
    
    $args{fields} ||= [ map {''.$_} $proto->columns( 'All' ) ];
    
    my @values = map { '' . $proto->get( $_ ) } @{ $args{fields} } if ref $proto;
 
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

sub _make_form
{
    my ( $me, $them, $orig, %args ) = @_;
    
    my $form = CGI::FormBuilder->new( %args );
    
    $form->{__cdbi_original_args__} = $orig;
    
    # this assumes meta_info only holds data on relationships
    foreach my $modify ( 'hidden', 'options', keys %{ $them->meta_info } ) 
    {
        my $form_modify = "form_$modify";
        
        $me->$form_modify( $them, $form );
    }
    
    return $form;
}

=item search_form( %args )

Build a form with inputs that can be fed to C<search_where_from_form>. For instance, 
all selects are multiple. 

In many cases, you will want to design your own search form, perhaps only searching 
on a subset of the available columns. Note that you can acheive that by specifying 

    fields => [ qw( only these fields ) ]
    
in the args. 

The following search options are available:

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
        
        my ( @series, $multiple );
    
        CASE: {
            # MySQL enum
            last CASE if @series = eval { $them->enum_vals( $field ) };  
            # MySQL set
            $multiple++, last CASE if @series = eval { $them->set_vals( $field ) };
        }
        
        next unless @series;
        
        $form->field( name      => $field,
                      options   => \@series,
                      multiple  => $multiple,
                      );
    }    
}

# meta_info is/includes:
# e.g.  has_a    accessor    CDBI::Rel object
# $hash{$type}->{$subtype} = $val;

# see example at end of file

=item form_has_a

Populates a select-type widget with entries representing related objects. Makes the field 
required.

Note that this list will be very long if there are lots of rows in the related table. 
You may need to override this method in that case. For instance, overriding with a 
no-op will result in a standard C<text> type input widget.

This method assumes the primary key is a single column - patches welcome. 

Retrieves every row and creates an object for it - not good for large tables.

=cut

sub form_has_a
{
    my ( $me, $them, $form ) = @_;
    
    my $meta = $them->meta_info( 'has_a' ) || return;
    
    my $pk = $them->primary_column;
    
    my @haves = keys %$meta;
    
    foreach my $field ( @haves ) 
    {
        $me->_set_field_options( $them, $form, $field, 'has_a', { required => 1 } ) || next;
                      
        next unless ref( $them );
        
        my $related_object = $them->get( $field ) || die sprintf
            'Failed to retrieve a related object from %s has_a field %s - inconsistent db?',
                ref( $them ), $field;
        
        $form->field( name  => $field,
                      value => $related_object->$pk,
                      );
    }
}

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
    
    $form->field( name => $_, multiple => 1 ) for @wanted;    
    
    # The target class/object ($them) does not have a column for the related class, 
    # so we need to add these to the form, then figure out their options.
    # Need to make sure and set some attribute to create the new field.
    # BUT - do not create the new field if it wasn't in the list passed in the original 
    # args, or if [] was passed in the original args. 
    
    foreach my $field ( @wanted )
    {
        # the 'next' is probably superfluous because @wanted is carefully filtered now
        $me->_set_field_options( $them, $form, $field, 'has_many' ) || next;
                      
        next unless ref( $them );
        
        my $rel = $meta->{ $field };
        
        my $accessor      = $rel->accessor      || die "no accessor for $field";
        my $related_class = $rel->foreign_class || die "no foreign_class for $field";
        
        my $foreign_pk = $related_class->primary_column;
        
        my @many_pks = map { $_->{ $foreign_pk } } $them->$accessor->data;
        
        $form->field( name  => $field,
                      value => \@many_pks,
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
    
    $form->field( name => $_, multiple => undef ) for @wanted;    
    
    foreach my $field ( @wanted ) 
    {
        # the 'next' is probably superfluous because @wanted is carefully filtered now
        $me->_set_field_options( $them, $form, $field, 'might_have' ) || next;
                      
        next unless ref( $them );
        
        my $rel = $meta->{ $field };
        
        my $accessor      = $rel->accessor      || die "no accessor for $field";
        my $related_class = $rel->foreign_class || die "no foreign_class for $field";
        
        my $foreign_pk = $related_class->primary_column;
        
        my $might_have_object = $them->$accessor;
        my $might_have_object_id = $might_have_object ? $might_have_object->$foreign_pk : '';
        
        $form->field( name  => $field,
                      value => $might_have_object_id,
                      );
    }
}

# note - we assume this method is only called on fields that require extra options
#      - the field might not exist (if building a form with only some of the available
#        fields)
sub _set_field_options
{
    my ( $me, $them, $form, $field, $rel_type, $field_args ) = @_;
    
    # Originally this was for passing the 'multiple' flag in has_many, 
    # but not used for anything at the moment. Seems useful though.
    $field_args ||= {};

    return unless exists $form->field->{ $field };
    
    my $options = $me->_field_options( $them, $form, $field, $rel_type ) || 
            die "No options detected for $rel_type field '$field'";
            
    $form->field( name    => $field,
                  options => $options,
                  %$field_args,
                  );
    
    return 1;
}

sub _field_options
{
    my ( $me, $them, $form, $field, $rel_type ) = @_;
    
    return unless exists $form->field->{ $field };
    
    my $rel = $them->meta_info( $rel_type, $field ) || return;
    
    return unless $rel->foreign_class->isa( 'Class::DBI' );

    my $related_class = $rel->foreign_class;
        
    my $iter = $related_class->retrieve_all;
    
    my @options;
    
    while ( my $object = $iter->next )
    {
        push @options, [ $object->id, "$object" ];
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
    my $class = shift;
    
    Carp::croak "create_from_form can only be called as a class method" if ref $class;
    
    __PACKAGE__->_run_create( $class, @_ );
}

sub _run_create 
{
    my ( $me, $class, $fb ) = @_;
    
    return unless $fb->submitted && $fb->validate;
    
    my $them = bless {}, $class;
    
    my $cols = {};
    
    # this assumes no extra fields in the form
    #return $class->create( $fb->fields );
    
    my $data = $fb->fields;
    
    foreach my $col ( map {''.$_} $them->columns('All') ) 
    {
        $cols->{ $col } = $data->{ $col };
    }
    
    my $obj = $class->create( $cols );    
    
    # If pk values are created in the database (e.g. in a MySQL AUTO_INCREMENT 
    # column), then they will not be available in the new object. Neither will 
    # anything else, because CDBI discards all data before returning the new 
    # object. 
    my @pcs = map { $obj->get( $_ ) } $obj->primary_columns;
    
    my $ok; 
    $ok &&= $_ for @pcs;
    
    return $obj if $ok; # every primary column has a value
    
    die "No pks for new object" unless @pcs == 1; # 1 undef value - we can find it
    
    # this works for MySQL and SQLite - these may be the only dbs that don't 
    # supply the pk data
    my $id = $obj->_auto_increment_value;
    
    return $class->retrieve( $id ) || die "Could not retrieve newly created object with ID $id";
}

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

    my $formdata = $fb->fields;

    my $object = $them->retrieve_from_form( $fb );
    
    return $object->update_from_form( $fb ) if $object;
    
    $them->create_from_form( $fb );
}

=back

=head2 Search methods

Note that search methods (except for C<retrieve_from_form>) will return a CDBI iterator 
in scalar context, and a (possibly empty) list of objects in list context.

All the search methods require that the submitted form should either be built using 
C<search_form> (not C<as_form>), or should supply all C<required> (including C<has_a>) fields.

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
    
    return unless $fb->submitted && $fb->validate;
    
#    my @primary = $them->primary_columns;
#    
#    my %pkdata = $me->_get_search_spec( $them, $fb, \@primary );
#    
#    # CDBI croaks with missing pks
#    return unless keys( %pkdata ) == @primary;

    my $formdata = $fb->fields;
    
    # this can send undef's for pk values, which seems to be OK
    my %pkdata = map { $_ => $formdata->{ $_ } } $them->primary_columns;
    
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

=head1 TODO

Use knowledge about select-like fields ( enum, set, has_a, has_many ) to generate 
validation rules.

Better merging of attributes. For instance, it'd be nice to set some field attributes 
(e.g. size) in C<form_builder_defaults>, and not lose them when the fields list is 
generated and added to C<%args>. 

Store CDBI errors somewhere on the form. For instance, if C<update_from_form> fails because 
no object could be retrieved using the form data. 

=head1 AUTHOR

David Baird, C<< <cpan@riverside-cms.co.uk> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-class-dbi-plugin-formbuilder@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-DBI-Plugin-FormBuilder>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

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


