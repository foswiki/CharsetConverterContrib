# See bottom of file for default license and copyright information

=begin TML

---+ package Foswiki::Contrib::CharsetConverterContrib

Static charset converter. Converts the character set used in a Foswiki
DB to UTF8.

ONLY FOR USE ON RCS STORES (RcsWrap, RcsLite)

=cut

package Foswiki::Contrib::CharsetConverterContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;
use File::Copy;

our $VERSION = '1.2';
our $RELEASE = '1 Jun 2015';
our $SHORTDESCRIPTION =
  'Convert entire Foswiki RCS databases from one character set to UTF-8';

our $options;
our $session;

sub report {
    return if $options->{-q};
    print STDERR join( ' ', @_ ) . "\n";
}

sub warning {
    print STDERR "WARNING: " . join( ' ', @_ ) . "\n";
}

sub error {
    if ( $options->{-a} ) {
        die join( ' ', @_ );
    }
    else {
        print STDERR "ERROR: " . join( ' ', @_ );
    }
}

sub detect_encoding {
    my $str = shift;

    return;
}

# Add any hand-tuned fixups here to adjust for strange
# encodings detected in your local data.  Passed 2 arguments
# - The detected encoding,  and the data.
#
sub _fixupDetect {

    #my $enc, $data = @_;

    # return 'iso-8859-1' if ( $_[0] =~ /^BIG/ );
    # return 'utf-8' if ( $_[0] =~ /^EUC/ );
    # return 'windows-1252' if ( $_[0] eq 'Shift-JIS' );
    return $_[0];

}

# Convert a byte string encoded in the {Site}{CharSet} to a byte
# string encoded in utf8
# Return 1 if a conversion happened, 0 otherwise
sub _convert_string {
    my ( $old, $where ) = @_;
    return 0 unless defined $old;
    my $e = $Foswiki::cfg{Site}{CharSet};

    if ( $options->{-r} ) {
        require Encode::Detect::Detector;
        my $de = Encode::Detect::Detector::detect($old);
        if ( $de && $de ne $Foswiki::cfg{Site}{CharSet} ) {
            warning("$de encoding detected in $where");

            # Chance to tweak the encooding.
            $e = _fixupDetect( $de, $old );
            warning("Encoding $de overridden to $e by _fixupDetect()")
              unless ( $e eq $de );
        }
    }

    # Convert octets encoded using site charset to unicode codepoints.
    # Note that we use Encode::FB_HTMLCREF; this should be a nop as
    # unicode can accomodate all characters.
    my $t;
    eval { $t = Encode::decode( $e, $old, Encode::FB_CROAK ); };
    if ($@) {

        # Broken encoding; try using the {Site}{CharSet} with
        # HTMLCREF (good luck with that!)
        $t = Encode::decode( $e, $old, Encode::FB_HTMLCREF );
    }

    # Convert to utf-8 bytes.
    $_[0] = Encode::encode_utf8($t);

    return ( $_[0] ne $old ) ? 1 : 0;
}

sub _rename {
    my ( $from, $to ) = @_;
    my $uto = Encode::decode_utf8($to);
    report "Move $uto";
    return if ( $options->{-i} );
    File::Copy::move( $from, $to )
      || error "Failed to rename $uto: $!";
}

=begin TML

---++ StaticMethod convert_database(%args)

Given the name of a collection (/ separated web name or empty
string for the root) convert
the topics and filenames in that collection to a UTF8 namespace.

=cut

sub convert_database {
    my (%args) = @_;

    $options = \%args;

    # Must do this before we construct the session object, otherwise the store
    # cache gets populated with Wrap handlers
    $Foswiki::cfg{Store}{Implementation} = 'Foswiki::Store::RcsLite';
    $session = new Foswiki();

    # First we rename all webs and files as necessary by
    # calling the recursive collection rename on the root web
    foreach my $tree ( $Foswiki::cfg{DataDir}, $Foswiki::cfg{PubDir} ) {
        _rename_collection( $tree, '' );
    }

    # All file and directory names should now be utf8

    # Now we convert the content of topics
    _convert_topics_contents('');

    # And that's it!

    $session->finish();
}

# Rename a web and all it's contents if necessary
sub _rename_collection {
    my ( $tree, $web ) = @_;
    my $dir;

    my $webpath = $tree . '/' . $web . '/';
    next unless -d $webpath;
    my %rename;
    my @subcoll;
    opendir( $dir, $webpath ) || die "Failed to open '$webpath' $!";

    #print STDERR "Collecting $webpath\n";
    foreach my $e ( readdir($dir) ) {
        next if $e =~ /^\./;

        #print STDERR "Collected $e $Foswiki::cfg{Site}{CharSet}\n";
        my $ne = $e;
        if ( _convert_string( $ne, "name $webpath$ne" ) ) {

            # $ne is encoded using utf8 but is *not* perl internal
            #my $blah = $ne;
            #$blah = Encode::decode('utf-8', $ne);
            #print STDERR "Converted $blah utf-8\n";
            $rename{ $webpath . $e } = $webpath . $ne;
        }
        if ( -d $webpath . $e ) {
            push( @subcoll, $web ? "$web/$ne" : $ne );
        }
    }
    closedir($dir);
    while ( my ( $old, $new ) = each %rename ) {
        _rename( $old, $new );
    }
    foreach $dir (@subcoll) {
        _rename_collection( $tree, $dir );
    }
}

# Convert the contents (*not* the name) of a topic
# The history conversion is done by loading the topic into
# RCSLite and performing the charset conversion on the fields.
sub _convert_topic {
    my ( $web, $topic ) = @_;
    my $converted = 0;
    print STDERR "START conversion of $web/$topic\n";

    # Convert .txt,v
    my $handler =
      Foswiki::Store::VC::RcsLiteHandler->new( $session->{store}, $web,
        $topic );
    my $uh = Encode::decode_utf8("$web.$topic");

    # Force reading of the topic history, all the way down to revision 1
    $handler->getRevision(1);

    if ( $handler->{state} ne 'nocommav' ) {

        # need to convert fields
        my $n  = 1;
        my $in = "content of $uh,v";
        foreach my $rev ( @{ $handler->{revs} } ) {
            $converted += _convert_string( $rev->{text}, $in )
              if defined $rev->{text};
            $converted += _convert_string( $rev->{log}, $in )
              if defined $rev->{log};
            $converted += _convert_string( $rev->{comment}, $in )
              if defined $rev->{comment};
            $converted += _convert_string( $rev->{desc}, $in )
              if defined $rev->{desc};
            $converted += _convert_string( $rev->{author}, $in )
              if defined $rev->{author};
        }
        if ($converted) {
            report "Converted history of $uh ($converted changes)";
            unless ( $options->{-i} ) {
                eval { $handler->_writeMe(); };
                if ($@) {
                    error
"Failed to write $uh history. Existing history may be corrupt: $@";
                }
            }
        }
    }
    else {
        report "No $uh history to convert";
    }

    # Convert .txt
    my $raw = $handler->readFile( $handler->{file} );
    $converted = _convert_string( $raw, "content of $handler->{file}" );
    if ($converted) {
        report "Converted .txt of $uh";
        $handler->saveFile( $handler->{file}, $raw ) unless $options->{-i};
    }
}

# Convert the contents (*not* the names) of topics found in a web dir
sub _convert_topics_contents {
    my $web = shift;
    my $dir;

    opendir( $dir, "$Foswiki::cfg{DataDir}/$web" )
      || die "Failed to open '$web' $!";
    foreach my $e ( readdir($dir) ) {
        next if $e =~ /^\./;
        if ( $web && $e =~ /^(.*)\.txt$/ ) {
            _convert_topic( $web, $1 );
        }
        elsif (-d "$Foswiki::cfg{DataDir}/$web/$e"
            && -e "$Foswiki::cfg{DataDir}/$web/$e/WebPreferences.txt" )
        {
            _convert_topics_contents( $web ? "$web/$e" : $e );
        }
    }
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: CrawfordCurrie

Copyright (C) 2011-2014 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
