package Tokeniseise;
# Copyright (C) 2012,2013,2016 Olly Betts
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

use strict;
use warnings;

sub new {
    my ($class, $header, $desc, $copyright, $guard, $type, $width) = @_;
    my $fh;
    open $fh, '>', "$header~" or die $!;
    print $fh <<"EOF";
/** \@file
 *  \@brief $desc
 */
/* Warning: This file is generated by $0 - do not modify directly! */
$copyright
#ifndef $guard
#define $guard

enum $type {
EOF
    my $self = {
	FH => $fh,
	HEADER => $header,
	M => {},
	WIDTH => ($width || 1),
	ENUM_VALUES => {}
    };
    bless($self, $class);
    return $self;
}

sub add {
    my ($self, $t, $enum) = @_;
    !exists ${$self->{M}{length $t}}{$t} or die "Token $t already seen";
    ${$self->{M}{length $t}}{$t} = $enum;
    if (!exists $self->{ENUM_VALUES}{$enum}) {
	$self->{ENUM_VALUES}{$enum} = scalar keys %{$self->{ENUM_VALUES}};
    }
    return;
}

sub append {
    my ($self, $line) = @_;
    push @{$self->{APPEND}}, $line;
    return;
}

sub write {
    my $self = shift;
    my $fh = $self->{FH};
    print $fh join ",\n", map { "    $_ = $self->{ENUM_VALUES}{$_}" } sort {$self->{ENUM_VALUES}{$a} <=> $self->{ENUM_VALUES}{$b}} keys %{$self->{ENUM_VALUES}};
    print $fh "\n};\n";

    my $width = $self->{WIDTH};
    my $max = (1 << (8 * $width)) - 1;
    if (scalar keys %{$self->{ENUM_VALUES}} > $max + 1) {
	die "Token value ", (scalar keys %{$self->{ENUM_VALUES}}) - 1, " > $max";
    }
    my $m = $self->{M};
    my @lens = sort {$a <=> $b} keys %$m;
    my $max_len = $lens[-1];
    sub space_needed {
	my ($l, $m) = @_;
	# Add a fraction of the length to give a deterministic order.
	return 1 + (1 + $l) * scalar(keys %{$m->{$l}}) + $l / 1000.0;
    }
    # Put the largest entries last so the offsets are more likely to fit into a
    # byte.
    @lens = sort {space_needed($a, $m) <=> space_needed($b, $m)} @lens;
    # 1 means "no entries" since it can't be a valid offset.
    # 2 also can't be a valid offset, but isn't currently used.
    my @h = (1) x $max_len;
    my @r = ();
    my $offset = 0;
    for my $len (@lens) {
	push @r, undef;
	($offset == 1 or $offset == 2) and die "Offset $offset shouldn't be possible";
	$offset > $max and die "Offset $offset > $max (you should specify a larger width)";
	$h[$len - 1] = $offset;
	my $href = $m->{$len};
	my $tab_len = scalar(keys %$href);
	$tab_len - 1 < 0 and die "Offset $tab_len < 0";
	$tab_len - 1 > $max and die "Offset $tab_len > $max";
	push @r, "($tab_len - 1),";
	++$offset;
	for my $s (sort keys %$href) {
	    $offset += 1 + length($s);
	    my $v = $$href{$s};
	    push @r, "$v, " . join(",", map { my $o = ord $_; $o >= 32 && $o < 127 ? "'$_'" : $o } split //, $s) . ",";
	}
    }
    print $fh "\nstatic const unsigned char tab[] = {\n";
    print $fh "    $max_len,\n";
    my $c = 0;
    for (@h) {
	if ($c++ % 8 == 0) {
	    print $fh "\n    ";
	} else {
	    print $fh " ";
	}
	if ($width == 1) {
	    printf $fh "%3d,", $_;
	} elsif ($width == 2) {
	    if ($_ == 1) {
		print $fh "1,0,";
	    } else {
		printf $fh "(%d&255),(%d>>8),", $_, $_;
	    }
	} else {
	    die "Unhandled width==$width";
	}
    }
    print $fh "\n";

    $r[-1] =~ s/,$//;

    for (@r) {
	if (defined $_) {
	    print $fh "    ", $_;
	}
	print $fh "\n";
    }

    print $fh <<'EOF';
};
EOF
    if (exists $self->{APPEND}) {
	print $fh "\n";
	for (@{$self->{APPEND}}) {
	    print $fh $_, "\n";
	}
    }
    print $fh <<'EOF';

#endif
EOF
    close $fh or die $!;
    rename "$self->{HEADER}~", $self->{HEADER} or die $!;

    return;
}

1;
