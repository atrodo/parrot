#! perl
# Copyright (C) 2010-2011, Parrot Foundation.

use strict;
use warnings;
use lib qw( . lib ../lib ../../lib );
use Test::More;
use Parrot::Test;
use File::Spec::Functions;

plan skip_all => 'src/parrot_config.o does not exist' unless -e catfile(qw/src parrot_config.o/);

plan tests => 59;

=head1 NAME

t/src/extend_vtable.t - tests for src/extend_vtable.c

=head1 SYNOPSIS

    % prove t/src/extend_Vtable.t

=head1 DESCRIPTION

Tests for src/extend_vtable.c .

=cut

sub linedirective
{
    # Provide a #line directive for the C code in the heredoc
    # starting immediately after where this sub is called.
    my $linenum = shift() + 1;
    return "#line " . $linenum . ' "' . __FILE__ . '"' . "\n";
}


my $common = linedirective(__LINE__) . <<'CODE';
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parrot/embed.h"
#include "parrot/extend.h"
#include "parrot/extend_vtable.h"

static void fail(const char *msg);
static Parrot_String createstring(Parrot_Interp interp, const char * value);
static Parrot_Interp new_interp();
static void handler(Parrot_Interp interp, Parrot_PMC exception, void *unused);

static void fail(const char *msg)
{
    fprintf(stderr, "failed: %s\n", msg);
    exit(EXIT_FAILURE);
}

static Parrot_String createstring(Parrot_Interp interp, const char * value)
{
    return Parrot_new_string(interp, value, strlen(value), (const char*)NULL, 0);
}

static Parrot_Interp new_interp()
{
    Parrot_Interp interp = Parrot_new(NULL);
    if (!interp)
        fail("Cannot create parrot interpreter");
    return interp;

}
static void handler(Parrot_Interp interp, Parrot_PMC exception, void *unused)
{
    Parrot_printf(interp, "Failed!\n");
    if (exception) {
        Parrot_String key;
        Parrot_Int type;
        Parrot_Int severity;
        Parrot_String message;

        key = createstring(interp, "type");
        type = Parrot_PMC_get_integer_keyed_str(interp, exception, key);
        key = createstring(interp, "severity");
        severity = Parrot_PMC_get_integer_keyed_str(interp, exception, key);
        message = Parrot_PMC_get_string(interp, exception);
        Parrot_printf(interp, "Exception is: type %d severity %d message '%Ss'\n",
                type, severity, message);
    }
}

CODE

sub extend_vtable_output_is
{
    my ($code, $expected_output, $msg, @opts) = @_;
    c_output_is(
        $common . linedirective(__LINE__) . <<CODE,
void dotest(Parrot_Interp interp, void *unused)
{
    Parrot_PMC pmc, pmc2, pmc3, pmc_string, pmc_string2;
    Parrot_PMC pmc_float, pmc_float2;
    Parrot_PMC rpa, rpa2;
    Parrot_Int type, value, integer, integer2;
    Parrot_Float number, number2;
    Parrot_String string, string2;

    type   = Parrot_PMC_typenum(interp, "Integer");
    rpa    = Parrot_PMC_new(interp, Parrot_PMC_typenum(interp, "ResizablePMCArray"));
    rpa2   = Parrot_PMC_new(interp, Parrot_PMC_typenum(interp, "ResizablePMCArray"));
    pmc    = Parrot_PMC_new(interp, type);
    pmc2   = Parrot_PMC_new(interp, type);
    pmc3   = Parrot_PMC_new(interp, type);

    pmc_string = Parrot_PMC_new(interp, Parrot_PMC_typenum(interp,"String"));
    pmc_string2 = Parrot_PMC_new(interp, Parrot_PMC_typenum(interp,"String"));

    pmc_float  = Parrot_PMC_new(interp, Parrot_PMC_typenum(interp,"Float"));
    pmc_float2 = Parrot_PMC_new(interp, Parrot_PMC_typenum(interp,"Float"));

$code

    /* TODO: Properly test this */
    Parrot_PMC_destroy(interp, pmc);

    Parrot_destroy(interp);
    printf("Done!\\n");
}

int main(void)
{
    Parrot_Interp interp;
    interp = new_interp();
    Parrot_ext_try(interp, &dotest, &handler, NULL);
    return 0;
}
CODE
        $expected_output, $msg, @opts
    );

}

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(freeze|thaw)");
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    Parrot_PMC_set_integer_native(interp, pmc2, 99);
    Parrot_printf(interp,"%P\n", pmc);
    Parrot_printf(interp,"%P\n", pmc2);

    /* freeze pmc, thaw tp pmc 2 */
    Parrot_PMC_freeze(interp, pmc, rpa);
    Parrot_PMC_thaw(interp, pmc2, rpa);
    /* Modify pmc to ensure they are not pointing to the same location */
    Parrot_PMC_set_integer_native(interp, pmc, 1000);
    Parrot_printf(interp,"%P\n", pmc);
    Parrot_printf(interp,"%P\n", pmc2);
CODE
42
99
1000
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_clone");
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    pmc2 = Parrot_PMC_clone(interp, pmc);

    Parrot_printf(interp,"%P\n", pmc2);
CODE
42
Done!
OUTPUT


extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_add_float" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    number = 43.0;

    Parrot_PMC_i_add_float(interp, pmc, number);
    number = Parrot_PMC_get_number(interp, pmc);
    Parrot_printf(interp,"%.2f\n", number);
CODE
1.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(push|pop)_integer" );
    integer  = 42;
    integer2 = 99;

    Parrot_PMC_push_integer(interp, rpa, integer);
    integer2 = Parrot_PMC_pop_integer(interp, rpa);

    Parrot_printf(interp,"%d\n", integer2);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_elements" );
    integer  = 42;

    integer = Parrot_PMC_elements(interp,rpa);
    Parrot_printf(interp,"%d\n", integer);

    Parrot_PMC_push_integer(interp, rpa, integer);

    integer = Parrot_PMC_elements(interp,rpa);
    Parrot_printf(interp,"%d\n", integer);
CODE
0
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(shift|unshift)_integer" );
    integer  = 42;
    integer2 = 99;

    Parrot_PMC_unshift_integer(interp, rpa, integer);
    integer2 = Parrot_PMC_shift_integer(interp, rpa);

    Parrot_printf(interp,"%d\n", integer2);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(push|pop)_pmc" );
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    Parrot_PMC_set_integer_native(interp, pmc2, 99);

    Parrot_PMC_push_pmc(interp, rpa, pmc);
    pmc2 = Parrot_PMC_pop_pmc(interp, rpa);

    Parrot_printf(interp,"%P\n", pmc2);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(unshift|pop)_pmc" );
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    Parrot_PMC_set_integer_native(interp, pmc2, 99);

    Parrot_PMC_unshift_pmc(interp, rpa, pmc);
    pmc2 = Parrot_PMC_pop_pmc(interp, rpa);

    Parrot_printf(interp,"%P\n", pmc2);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(push|pop)_string" );
    string = createstring(interp, "FOO");
    string2 = createstring(interp, "BAR");

    Parrot_PMC_push_string(interp, rpa, string);
    string2 = Parrot_PMC_pop_string(interp, rpa);

    Parrot_printf(interp,"%S\n", string2);
CODE
FOO
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(unshift|shift)_string" );
    string = createstring(interp, "FOO");
    string2 = createstring(interp, "BAR");

    Parrot_PMC_unshift_string(interp, rpa, string);
    string2 = Parrot_PMC_shift_string(interp, rpa);

    Parrot_printf(interp,"%S\n", string2);
CODE
FOO
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(push|pop)_float" );
    number  = 42.0;
    number2 = 99.0;

    Parrot_PMC_push_float(interp, rpa, number);
    number2 = Parrot_PMC_pop_float(interp, rpa);

    Parrot_printf(interp,"%.2f\n", number2);
CODE
42.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(unshift|shift)_float" );
    number  = 42.0;
    number2 = 99.0;

    Parrot_PMC_unshift_float(interp, rpa, number);
    number2 = Parrot_PMC_shift_float(interp, rpa);

    Parrot_printf(interp,"%.2f\n", number2);
CODE
42.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_add_int" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    integer = 43;

    pmc3 = Parrot_PMC_add_int(interp, pmc, integer, pmc3);
    integer = Parrot_PMC_get_integer(interp, pmc3);
    Parrot_printf(interp,"%d\n", integer);
CODE
1
Done!
OUTPUT


extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_absolute" );

    Parrot_PMC_set_integer_native(interp, pmc, -42);
    pmc2 = Parrot_PMC_absolute(interp, pmc, pmc2);

    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", (int) value);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_absolute" );

    Parrot_PMC_set_integer_native(interp, pmc, -42);
    Parrot_PMC_i_absolute(interp, pmc);

    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(increment|decrement)" );

    Parrot_PMC_set_integer_native(interp, pmc, -42);

    Parrot_PMC_increment(interp, pmc);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);

    Parrot_PMC_decrement(interp, pmc);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
CODE
-41
-42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_neg" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    Parrot_PMC_i_neg(interp, pmc);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_neg" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    pmc2 = Parrot_PMC_neg(interp, pmc, pmc2);
    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", (int) value);
CODE
42
Done!
OUTPUT


extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_floor_divide" );
    Parrot_PMC_set_integer_native(interp, pmc,  7);
    Parrot_PMC_set_integer_native(interp, pmc2, 3);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_floor_divide(interp, pmc, pmc2, pmc3);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);
CODE
7
3
2
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_floor_divide_float" );
    Parrot_PMC_set_integer_native(interp, pmc,  7);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);
    number = 3.0;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_floor_divide_float(interp, pmc, number, pmc3);
    number = Parrot_PMC_get_number(interp, pmc3);
    printf("%.2f\n", number);
CODE
2.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_floor_divide_int" );
    Parrot_PMC_set_integer_native(interp, pmc,  7);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);
    integer = 3;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_floor_divide_float(interp, pmc, integer, pmc3);
    integer = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", integer);
CODE
2
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_multiply" );

    Parrot_PMC_set_integer_native(interp, pmc,  21);
    Parrot_PMC_set_integer_native(interp, pmc2, 2);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_multiply(interp, pmc, pmc2, pmc3);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);
CODE
21
2
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_multiply_int" );

    Parrot_PMC_set_integer_native(interp, pmc,  21);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);
    integer = 2;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_multiply_int(interp, pmc, integer, pmc3);
    integer = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", integer);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_multiply" );

    Parrot_PMC_set_integer_native(interp, pmc,  21);
    Parrot_PMC_set_integer_native(interp, pmc2, 2);

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    Parrot_PMC_i_multiply(interp, pmc, pmc2);
    integer = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", integer);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_multiply_int" );

    Parrot_PMC_set_integer_native(interp, pmc,  21);
    integer = 2;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    Parrot_PMC_i_multiply_int(interp, pmc, integer);
    integer = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", integer);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_multiply_float" );

    Parrot_PMC_set_integer_native(interp, pmc,  21);
    number = 2.0;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    Parrot_PMC_i_multiply_float(interp, pmc, number);
    number = Parrot_PMC_get_integer(interp, pmc);
    printf("%.2f\n", number);
CODE
42.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_multiply_float" );

    Parrot_PMC_set_integer_native(interp, pmc,  21);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);
    number = 2.0;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_multiply_float(interp, pmc, number, pmc3);
    number = Parrot_PMC_get_number(interp, pmc3);
    printf("%.2f\n", number);
CODE
42.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_divide" );
    Parrot_PMC_set_integer_native(interp, pmc,  42);
    Parrot_PMC_set_integer_native(interp, pmc2, 21);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);

    pmc3 = Parrot_PMC_divide(interp, pmc, pmc2, pmc3);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);
CODE
42
21
2
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_visit" );
    /* TODO: Test this properly */
    Parrot_PMC_visit(interp, pmc, pmc2);
    printf("42\n", (int) value);
CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_divide" );
    Parrot_PMC_set_integer_native(interp, pmc,  42);
    Parrot_PMC_set_integer_native(interp, pmc2, 21);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);

    Parrot_PMC_i_divide(interp, pmc, pmc2);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
CODE
2
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_divide_int" );
    Parrot_PMC_set_integer_native(interp, pmc,  42);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);
    integer = 21;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_divide_int(interp, pmc, integer, pmc3);
    integer = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", integer);
CODE
2
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_divide_float" );
    Parrot_PMC_set_integer_native(interp, pmc,  42);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);
    number = 21.0;

    /*
       We must pass in the destination, but the return
       value of the function must be used. This is broken.
    */
    pmc3 = Parrot_PMC_divide_float(interp, pmc, number, pmc3);
    number = Parrot_PMC_get_number(interp, pmc3);
    printf("%.2f\n", number);
CODE
2.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE',<<'OUTPUT', "Parrot_PMC_modulus" );
    Parrot_PMC_set_integer_native(interp, pmc,  50);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);

    pmc3 = Parrot_PMC_modulus(interp, pmc, pmc2, pmc3);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", (int) value);
    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);
CODE
50
42
8
Done!
OUTPUT

extend_vtable_output_is(<<'CODE',<<'OUTPUT', "Parrot_PMC_i_modulus" );
    Parrot_PMC_set_integer_native(interp, pmc,  50);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);
    Parrot_PMC_set_integer_native(interp, pmc3, 0);

    Parrot_PMC_i_modulus(interp, pmc, pmc2);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", value);
    value = Parrot_PMC_get_integer(interp, pmc2);
    printf("%d\n", value);
CODE
8
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE',<<'OUTPUT', "Parrot_PMC_i_modulus_int" );
    Parrot_PMC_set_integer_native(interp, pmc,  50);
    integer = 42;

    Parrot_PMC_i_modulus_int(interp, pmc, integer);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int)value);
CODE
8
Done!
OUTPUT

# TODO: Does this look right?
extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_defined" );
    Parrot_PMC_set_integer_native(interp, pmc2, -42);

    integer = Parrot_PMC_defined(interp, pmc);
    printf("%d\n", (int) integer);

    integer = Parrot_PMC_defined(interp, pmc2);
    printf("%d\n", (int) integer);

CODE
1
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_is_same" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);

    integer = Parrot_PMC_is_same(interp, pmc, pmc2);
    printf("%d\n", (int) integer);

    Parrot_PMC_set_integer_native(interp, pmc2, -42);

    integer = Parrot_PMC_is_same(interp, pmc, pmc2);
    printf("%d\n", (int) integer);

    integer = Parrot_PMC_is_same(interp, pmc, pmc);
    printf("%d\n", (int) integer);
CODE
0
0
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_is_equal" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);

    integer = Parrot_PMC_is_equal(interp, pmc, pmc2);
    printf("%d\n", (int) integer);

    Parrot_PMC_set_integer_native(interp, pmc2, -42);

    integer = Parrot_PMC_is_equal(interp, pmc, pmc2);
    printf("%d\n", (int) integer);
CODE
0
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_is_equal_num");
    Parrot_PMC_set_number_native(interp, pmc, -42);
    Parrot_PMC_set_number_native(interp, pmc2, 42);

    integer = Parrot_PMC_is_equal_num(interp, pmc, pmc2);
    Parrot_printf(interp, "%d\n", integer);

    Parrot_PMC_set_number_native(interp, pmc2, -42);

    integer = Parrot_PMC_is_equal_num(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer);
CODE
0
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_is_equal_string" );
     string  = createstring(interp, "FOO");
     string2 = createstring(interp, "BAR");

     Parrot_PMC_assign_string_native(interp, pmc_string, string);
     Parrot_PMC_assign_string_native(interp, pmc_string2,string2);

     integer = Parrot_PMC_is_equal(interp, pmc_string, pmc_string2);
     Parrot_printf(interp, "%d\n", (int)integer);

     Parrot_PMC_set_string_native(interp, pmc_string2, string);

     integer = Parrot_PMC_is_equal(interp, pmc_string, pmc_string2);
     Parrot_printf(interp, "%d\n", (int)integer);
CODE
0
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_subtract" );

    Parrot_PMC_set_integer_native(interp, pmc,  52);
    Parrot_PMC_set_integer_native(interp, pmc2, 10);

    pmc3 = Parrot_PMC_subtract(interp, pmc, pmc2, pmc3);
    Parrot_printf(interp, "%P\n", pmc3);
    pmc3 = Parrot_PMC_subtract(interp, pmc2, pmc, pmc3);
    Parrot_printf(interp, "%P\n", pmc3);

CODE
42
-42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_subtract" );

    Parrot_PMC_set_integer_native(interp, pmc,  52);
    Parrot_PMC_set_integer_native(interp, pmc2, 10);

    Parrot_PMC_i_subtract(interp, pmc, pmc2);
    Parrot_printf(interp, "%P\n", pmc);

CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_subtract_int" );

    Parrot_PMC_set_integer_native(interp, pmc,  52);
    integer = 10;

    pmc3 = Parrot_PMC_subtract_int(interp, pmc, integer, pmc3);
    Parrot_printf(interp, "%P\n", pmc3);

CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_subtract_float" );

    Parrot_PMC_set_integer_native(interp, pmc,  52);
    number = 10.0;

    pmc3 = Parrot_PMC_subtract_float(interp, pmc, number, pmc3);
    Parrot_printf(interp, "%P\n", pmc3);

CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_subtract_int" );

    Parrot_PMC_set_integer_native(interp, pmc,  52);
    integer = 10;

    Parrot_PMC_i_subtract_int(interp, pmc, integer);
    Parrot_printf(interp, "%P\n", pmc);

CODE
42
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_subtract_float" );

    Parrot_PMC_set_integer_native(interp, pmc,  52);
    number = 10.0;

    Parrot_PMC_i_subtract_float(interp, pmc, number);
    Parrot_printf(interp, "%P\n", pmc);

CODE
42
Done!
OUTPUT


extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_cmp" );
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    Parrot_PMC_set_integer_native(interp, pmc2, 17);

    integer = Parrot_PMC_cmp(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", (int) integer);

    Parrot_PMC_set_integer_native(interp, pmc, 17);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);

    integer = Parrot_PMC_cmp(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", (int) integer);

    Parrot_PMC_set_integer_native(interp, pmc, 42);

    integer = Parrot_PMC_cmp(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", (int) integer);
CODE
1
-1
0
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_cmp_string" );
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    Parrot_PMC_set_integer_native(interp, pmc2, 17);

    integer = Parrot_PMC_cmp_string(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer );

    Parrot_PMC_set_integer_native(interp, pmc, 17);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);

    integer = Parrot_PMC_cmp_string(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer );

    Parrot_PMC_set_integer_native(interp, pmc, 42);

    integer = Parrot_PMC_cmp_string(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer );
CODE
1
-1
0
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_cmp_num" );
    Parrot_PMC_set_integer_native(interp, pmc, 42);
    Parrot_PMC_set_integer_native(interp, pmc2, 17);

    integer = Parrot_PMC_cmp_num(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer );

    Parrot_PMC_set_integer_native(interp, pmc, 17);
    Parrot_PMC_set_integer_native(interp, pmc2, 42);

    integer = Parrot_PMC_cmp_num(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer );

    Parrot_PMC_set_integer_native(interp, pmc, 42);

    integer = Parrot_PMC_cmp_num(interp, pmc, pmc2);
    Parrot_printf(interp,"%d\n", integer );
CODE
1
-1
0
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_add" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    Parrot_PMC_set_integer_native(interp, pmc2, 1000);

    Parrot_PMC_i_add(interp, pmc, pmc2);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
CODE
958
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_i_add_int" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    Parrot_PMC_i_add_int(interp, pmc, 1000);
    value = Parrot_PMC_get_integer(interp, pmc);
    printf("%d\n", (int) value);
CODE
958
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_add_float" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    number = 1000.0;

    pmc3 = Parrot_PMC_add_float(interp, pmc, number, pmc3);
    number = Parrot_PMC_get_number(interp, pmc3);
    printf("%.2f\n", number);
CODE
958.00
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_add" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    Parrot_PMC_set_integer_native(interp, pmc2, 1000);

    pmc3 = Parrot_PMC_add(interp, pmc, pmc2, pmc3);
    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);
CODE
958
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_(set|get)_bool" );
    Parrot_PMC_set_bool(interp, pmc, 1);
    integer = Parrot_PMC_get_bool(interp, pmc);
    printf("%d\n", (int) integer);

    Parrot_PMC_set_bool(interp, pmc, 0);
    integer = Parrot_PMC_get_bool(interp, pmc);
    printf("%d\n", (int) integer);
CODE
1
0
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_type" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    integer = Parrot_PMC_type(interp, pmc);

    if (integer > 0)
        Parrot_printf(interp,"42\n", integer);
CODE
42
Done!
OUTPUT


extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_get_class" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    pmc_string = Parrot_PMC_get_class(interp, pmc);

    Parrot_printf(interp,"%P\n", pmc_string);
CODE
Integer
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_can" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    string = createstring(interp, "foo");
    integer = Parrot_PMC_can(interp,pmc,string);
    printf("%d\n", (int) integer);

    string = createstring(interp, "add");
    integer = Parrot_PMC_can(interp,pmc,string);
    printf("%d\n", (int) integer);
CODE
0
1
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_does" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);

    string = createstring(interp, "foo");
    integer = Parrot_PMC_does(interp,pmc,string);
    printf("%d\n", (int) integer);

    /* TODO: This doesn't seem to work
    string = createstring(interp, "Integer");
    integer = Parrot_PMC_does(interp,pmc,string);
    printf("%d\n", (int) integer);
    */
CODE
0
Done!
OUTPUT

extend_vtable_output_is(<<'CODE', <<'OUTPUT', "Parrot_PMC_assign_pmc" );
    Parrot_PMC_set_integer_native(interp, pmc, -42);
    Parrot_PMC_set_integer_native(interp, pmc2, 1000);
    Parrot_PMC_set_integer_native(interp, pmc3, 420);

    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);

    Parrot_PMC_assign_pmc(interp, pmc3, pmc);

    value = Parrot_PMC_get_integer(interp, pmc3);
    printf("%d\n", (int) value);
CODE
420
-42
Done!
OUTPUT

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
